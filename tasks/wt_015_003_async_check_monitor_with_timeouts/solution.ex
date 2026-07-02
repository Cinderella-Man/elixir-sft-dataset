defmodule AsyncMonitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic health checks
  where each check runs asynchronously in a spawned Task with a configurable
  timeout.

  Unlike a synchronous monitor, this design prevents slow check functions from
  blocking the GenServer. Each check is spawned as a separate process, and a
  timeout timer ensures the GenServer isn't stuck waiting indefinitely.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type service_name :: term()
  @type status :: :pending | :up | :down
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean()
        }

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           timeout_ms: pos_integer(),
           status: status(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           task_ref: reference() | nil,
           task_pid: pid() | nil
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, nil)

    {:ok, %{services: %{}, clock: clock, notify: notify}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      max_failures = Keyword.get(opts, :max_failures, 3)
      timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        timeout_ms: timeout_ms,
        status: :pending,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        task_ref: nil,
        task_pid: nil
      }

      schedule_check(name, interval_ms)

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
    {:reply, result, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        # Kill any in-flight task.
        if service.task_pid do
          Process.exit(service.task_pid, :kill)
        end

        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, service} ->
        # Spawn a Task to run the check function.
        gen_server = self()
        ref = make_ref()

        {:ok, pid} =
          Task.start(fn ->
            result =
              try do
                service.check_func.()
              rescue
                e -> {:error, {:exception, Exception.message(e)}}
              catch
                kind, value -> {:error, {kind, value}}
              end

            send(gen_server, {:check_result, name, ref, result})
          end)

        # Monitor the task so we know if it crashes.
        Process.monitor(pid)

        # Schedule a timeout message.
        Process.send_after(self(), {:check_timeout, name, ref}, service.timeout_ms)

        new_service = %{service | task_ref: ref, task_pid: pid}
        {:noreply, put_in(state.services[name], new_service)}
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref} = service} ->
        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, result, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          {:error, reason} = result
          fire_notify(state.notify, name, reason)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — result from an old task. Discard.
        {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, %{task_ref: ^ref, task_pid: pid} = service} ->
        # Kill the timed-out task.
        if pid, do: Process.exit(pid, :kill)

        now = state.clock.()
        {new_service, notify?} = apply_check_result(service, {:error, :timeout}, now)
        new_service = %{new_service | task_ref: nil, task_pid: nil}

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, :timeout)
        end

        {:noreply, new_state}

      {:ok, _service} ->
        # Stale ref — timeout for an already-completed or replaced task.
        {:noreply, state}
    end
  end

  # Handle DOWN messages from monitored tasks — just ignore them.
  # We handle lifecycle via check_result/check_timeout.
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_check_result(service(), :ok | {:error, term()}, integer()) ::
          {service(), boolean()}
  defp apply_check_result(service, :ok, now) do
    new_service = %{
      service
      | status: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }

    {new_service, false}
  end

  defp apply_check_result(service, {:error, _reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    notify? = threshold_reached && !service.notified_down

    new_status = if threshold_reached, do: :down, else: service.status

    new_service = %{
      service
      | status: new_status,
        last_check_at: now,
        consecutive_failures: new_failures,
        notified_down: service.notified_down || notify?
    }

    {new_service, notify?}
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:schedule_check, name}, interval_ms)
  end

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      check_in_flight: service.task_ref != nil
    }
  end

  @spec fire_notify((service_name(), term() -> any()) | nil, service_name(), term()) :: any()
  defp fire_notify(nil, _name, _reason), do: :ok
  defp fire_notify(notify_fn, name, reason), do: notify_fn.(name, reason)
end
