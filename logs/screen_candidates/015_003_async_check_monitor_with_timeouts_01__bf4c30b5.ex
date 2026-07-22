defmodule AsyncMonitor do
  @moduledoc """
  A `GenServer` that monitors registered services with periodic, asynchronous health checks.

  Each registered service has a zero-arity check function, an interval, a maximum number of
  consecutive failures before it is considered `:down`, and a per-check timeout.

  When a service's scheduled check fires, the monitor spawns a `Task` that runs the check
  function and reports the result back to the monitor. The monitor also arms a timeout
  message; if the task has not reported by then, the task is killed and the check is treated
  as a failure with reason `:timeout`.

  At most one check task is in flight per service. Results carrying a stale task reference
  (because the service was deregistered, re-registered, or the check already timed out) are
  silently discarded.

  Status transitions:

    * a service starts in `:pending` after registration;
    * a successful check sets the status to `:up` and resets the consecutive failure count;
    * a failing check increments the consecutive failure count, and once it reaches
      `:max_failures` the status becomes `:down` and the `:notify` function is invoked once
      with `(service_name, reason)`;
    * further failures while `:down` do not re-notify, but a recovery to `:up` followed by a
      new run of failures will notify again.

  Time is read through an injectable `:clock` function so tests can control timestamps.
  """

  use GenServer

  @default_max_failures 3
  @default_timeout_ms 5_000

  @typedoc "The name a service is registered under."
  @type service_name :: term()

  @typedoc "A zero-arity health check function."
  @type check_func :: (-> :ok | {:error, term()})

  @typedoc "The lifecycle status of a monitored service."
  @type status :: :up | :down | :pending

  @typedoc "Public status information for a monitored service."
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean(),
          last_result: :ok | {:error, term()} | nil,
          interval_ms: pos_integer(),
          max_failures: pos_integer(),
          timeout_ms: pos_integer()
        }

  defmodule Service do
    @moduledoc false

    defstruct [
      :name,
      :check_func,
      :interval_ms,
      :max_failures,
      :timeout_ms,
      status: :pending,
      last_check_at: nil,
      last_result: nil,
      consecutive_failures: 0,
      schedule_timer: nil,
      timeout_timer: nil,
      task_ref: nil,
      task_pid: nil,
      task_monitor: nil
    ]
  end

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the monitor.

  Options:

    * `:clock` - zero-arity function returning the current time in milliseconds. Defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` - function of the form `fn service_name, reason -> ... end` invoked when a
      service transitions to `:down`. Defaults to a no-op.
    * `:name` - optional name for process registration.

  Any other option is passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {notify, opts} = Keyword.pop(opts, :notify, fn _service_name, _reason -> :ok end)
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: Keyword.put(opts, :name, name), else: opts
    GenServer.start_link(__MODULE__, %{clock: clock, notify: notify}, server_opts)
  end

  @doc """
  Registers `service_name` for monitoring.

  `check_func` is a zero-arity function returning `:ok` or `{:error, reason}`. `interval_ms`
  is the delay between checks; the first check is scheduled `interval_ms` from registration.

  Options:

    * `:max_failures` - consecutive failures before the service is marked `:down` (default 3).
    * `:timeout_ms` - maximum time a single check may run (default 5000).

  Returns `:ok`, or `{:error, :already_registered}` if the name is already monitored.
  """
  @spec register(GenServer.server(), service_name(), check_func(), pos_integer(), keyword()) ::
          :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ [])
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 and
             is_list(opts) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Returns `{:ok, status_info}` for `service_name`, or `{:error, :not_found}` if unregistered.
  """
  @spec status(GenServer.server(), service_name()) :: {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `t:status_info/0` map.
  """
  @spec statuses(GenServer.server()) :: %{optional(service_name()) => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc """
  Removes `service_name` from monitoring.

  Cancels any pending scheduled check and kills any in-flight check task. Always returns `:ok`,
  whether or not the service was registered.
  """
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  def init(%{clock: clock, notify: notify}) do
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = %Service{
        name: name,
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: Keyword.get(opts, :max_failures, @default_max_failures),
        timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
        status: :pending,
        schedule_timer: schedule_check(name, interval_ms)
      }

      {:reply, :ok, put_service(state, service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    infos = Map.new(state.services, fn {name, service} -> {name, status_info(service)} end)
    {:reply, infos, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.pop(state.services, name) do
      {nil, _services} ->
        {:reply, :ok, state}

      {service, services} ->
        service
        |> cancel_schedule()
        |> cancel_in_flight()

        {:reply, :ok, %{state | services: services}}
    end
  end

  @impl GenServer
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %Service{task_ref: nil} = service} ->
        {:noreply, put_service(state, start_check(service))}

      # A check is already in flight; do not start a second one. The in-flight check will
      # schedule the next one when it resolves.
      {:ok, %Service{} = service} ->
        {:noreply, put_service(state, %{service | schedule_timer: nil})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:check_result, name, task_ref, result}, state) do
    case current_check(state, name, task_ref) do
      {:ok, service} -> {:noreply, put_service(state, resolve_check(service, result, state))}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, task_ref}, state) do
    case current_check(state, name, task_ref) do
      {:ok, service} ->
        if is_pid(service.task_pid), do: Process.exit(service.task_pid, :kill)
        service = %{service | timeout_timer: nil}
        {:noreply, put_service(state, resolve_check(service, {:error, :timeout}, state))}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case find_by_monitor(state, monitor_ref) do
      {:ok, %Service{} = service} ->
        # The task died before reporting (crash or timeout kill). A normal exit here means the
        # result message was already handled and the check cleared, so this clause is only
        # reached for abnormal or unreported terminations.
        service = %{service | task_monitor: nil}
        {:noreply, put_service(state, resolve_check(service, {:error, down_reason(reason)}, state))}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------------------

  defp put_service(state, %Service{name: name} = service) do
    %{state | services: Map.put(state.services, name, service)}
  end

  defp current_check(state, name, task_ref) do
    case Map.fetch(state.services, name) do
      {:ok, %Service{task_ref: ^task_ref} = service} when not is_nil(task_ref) -> {:ok, service}
      _other -> :error
    end
  end

  defp find_by_monitor(state, monitor_ref) do
    Enum.find_value(state.services, :error, fn {_name, service} ->
      if service.task_monitor == monitor_ref, do: {:ok, service}
    end)
  end

  defp down_reason(:killed), do: :timeout
  defp down_reason(reason), do: {:task_exit, reason}

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:schedule_check, name}, interval_ms)
  end

  defp start_check(%Service{} = service) do
    monitor = self()
    task_ref = make_ref()
    check_func = service.check_func
    name = service.name

    task =
      Task.Supervisor.async_nolink(AsyncMonitor.NoSupervisor, fn -> :noop end)
      |> then(fn _ -> nil end)

    _ = task

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result =
          try do
            case check_func.() do
              :ok -> :ok
              {:error, reason} -> {:error, reason}
              other -> {:error, {:bad_return, other}}
            end
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(monitor, {:check_result, name, task_ref, result})
      end)

    timeout_timer =
      Process.send_after(self(), {:check_timeout, name, task_ref}, service.timeout_ms)

    %{
      service
      | schedule_timer: nil,
        task_ref: task_ref,
        task_pid: pid,
        task_monitor: monitor_ref,
        timeout_timer: timeout_timer
    }
  end

  defp resolve_check(%Service{} = service, result, state) do
    now = state.clock.()

    service =
      service
      |> clear_in_flight()
      |> Map.put(:last_check_at, now)
      |> Map.put(:last_result, result)

    service = apply_result(service, result, state)
    %{service | schedule_timer: schedule_check(service.name, service.interval_ms)}
  end

  defp apply_result(%Service{} = service, :ok, _state) do
    %{service | status: :up, consecutive_failures: 0}
  end

  defp apply_result(%Service{} = service, {:error, reason}, state) do
    failures = service.consecutive_failures + 1
    was_down? = service.status == :down

    cond do
      was_down? ->
        %{service | consecutive_failures: failures}

      failures >= service.max_failures ->
        notify(state, service.name, reason)
        %{service | status: :down, consecutive_failures: failures}

      true ->
        %{service | consecutive_failures: failures}
    end
  end

  defp notify(state, name, reason) do
    _ =
      try do
        state.notify.(name, reason)
      catch
        _kind, _reason -> :ok
      end

    :ok
  end

  defp clear_in_flight(%Service{} = service) do
    cancel_timer(service.timeout_timer)
    demonitor(service.task_monitor)
    %{service | task_ref: nil, task_pid: nil, task_monitor: nil, timeout_timer: nil}
  end

  defp cancel_in_flight(%Service{} = service) do
    if is_pid(service.task_pid), do: Process.exit(service.task_pid, :kill)
    clear_in_flight(service)
  end

  defp cancel_schedule(%Service{} = service) do
    cancel_timer(service.schedule_timer)
    %{service | schedule_timer: nil}
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    :ok
  end

  defp demonitor(nil), do: :ok

  defp demonitor(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  defp status_info(%Service{} = service) do
    %{
      status: service.status,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      check_in_flight: not is_nil(service.task_ref),
      last_result: service.last_result,
      interval_ms: service.interval_ms,
      max_failures: service.max_failures,
      timeout_ms: service.timeout_ms
    }
  end
end