defmodule AsyncMonitor do
  @moduledoc """
  A `GenServer` that supervises registered services by running each service's
  health check **asynchronously in a spawned Task** with a per-service timeout.

  Because each check runs in its own monitored `Task`, a slow or hung check can
  never block the monitor itself or the checks of other services. The monitor
  tracks, per service, the current status (`:pending`, `:up`, or `:down`), the
  number of consecutive failures, the time of the last concluded check, and
  whether a check Task is currently in flight.

  ## Protocol

  Services are driven entirely through messages, which are part of the public
  contract:

    * `{:schedule_check, service_name}` — start one check for the service;
    * `{:check_result, service_name, task_ref, result}` — sent by the Task when
      its check function returns;
    * `{:check_timeout, service_name, task_ref}` — armed at spawn time; if it
      arrives while the same Task is still in flight the Task is killed and the
      check is treated as a `:timeout` failure.

  A `{:check_result, ...}` or `{:check_timeout, ...}` whose `task_ref` does not
  match the service's currently expected reference is silently discarded. This
  reference match is what keeps a deregistered or re-registered service's stale
  messages from affecting current state.
  """

  use GenServer

  @default_max_failures 3
  @default_timeout_ms 5_000

  # ------------------------------------------------------------------ #
  # Public API                                                         #
  # ------------------------------------------------------------------ #

  @doc """
  Starts and links the monitor.

  Options:

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — a two-arity function `notify.(service_name, reason)` invoked
      when a service transitions to `:down`. Defaults to a no-op.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @doc """
  Registers `service_name` with a zero-arity `check_func` returning `:ok` or
  `{:error, reason}`, checked every `interval_ms` milliseconds.

  Options:

    * `:max_failures` — consecutive failures (including timeouts) before the
      service is marked `:down`. Defaults to `#{@default_max_failures}`.
    * `:timeout_ms` — the maximum time a single check Task may run. Defaults to
      `#{@default_timeout_ms}`.

  Returns `:ok`, or `{:error, :already_registered}` if the name is taken. An
  existing registration is never replaced or altered by a second call. The first
  check is scheduled `interval_ms` milliseconds later; registration itself runs
  no check.
  """
  @spec register(
          GenServer.server(),
          term(),
          (-> :ok | {:error, term()}),
          non_neg_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Removes `service_name` from monitoring and always returns `:ok`, whether or
  not it was registered.

  Any in-flight check Task is shut down and the registration's scheduled
  messages never take effect again. The same name may be registered afresh
  afterwards.
  """
  @spec deregister(GenServer.server(), term()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service, or
  `{:error, :not_found}` otherwise.

  `status_info` contains at least `:status`, `:last_check_at`,
  `:consecutive_failures`, and `:check_in_flight`.
  """
  @spec status(GenServer.server(), term()) ::
          {:ok, map()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(GenServer.server()) :: %{optional(term()) => map()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  # ------------------------------------------------------------------ #
  # GenServer callbacks                                                #
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(opts) do
    clock =
      Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl GenServer
  def handle_call({:register, name, func, interval, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      svc = new_service(name, func, interval, opts)
      {:reply, :ok, update_service(state, name, svc)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, :ok, state}

      {:ok, svc} ->
        cancel_task(svc)
        cancel_sched(svc)
        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error -> {:reply, {:error, :not_found}, state}
      {:ok, svc} -> {:reply, {:ok, build_info(svc)}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    infos =
      Map.new(state.services, fn {name, svc} -> {name, build_info(svc)} end)

    {:reply, infos, state}
  end

  @impl GenServer
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, svc} ->
        if svc.check_in_flight do
          {:noreply, state}
        else
          {:noreply, start_check(state, name, svc)}
        end
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    svc = Map.get(state.services, name)

    if svc && svc.check_ref == ref do
      {:noreply, conclude(state, name, svc, outcome_from(result))}
    else
      {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    svc = Map.get(state.services, name)

    if svc && svc.check_ref == ref do
      if svc.task_pid, do: Process.exit(svc.task_pid, :kill)
      {:noreply, conclude(state, name, svc, {:failure, :timeout})}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ------------------------------------------------------------------ #
  # Internal helpers                                                   #
  # ------------------------------------------------------------------ #

  @spec new_service(term(), (-> term()), non_neg_integer(), keyword()) :: map()
  defp new_service(name, func, interval, opts) do
    max_failures = Keyword.get(opts, :max_failures, @default_max_failures)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    timer = Process.send_after(self(), {:schedule_check, name}, interval)

    %{
      check_func: func,
      interval_ms: interval,
      max_failures: max_failures,
      timeout_ms: timeout_ms,
      status: :pending,
      consecutive_failures: 0,
      last_check_at: nil,
      check_in_flight: false,
      check_ref: nil,
      task_pid: nil,
      task_mon: nil,
      sched_timer: timer
    }
  end

  @spec start_check(map(), term(), map()) :: map()
  defp start_check(state, name, svc) do
    ref = make_ref()
    server = self()
    func = svc.check_func

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            func.()
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(server, {:check_result, name, ref, result})
      end)

    Process.send_after(server, {:check_timeout, name, ref}, svc.timeout_ms)

    svc = %{
      svc
      | check_in_flight: true,
        check_ref: ref,
        task_pid: pid,
        task_mon: mon
    }

    update_service(state, name, svc)
  end

  @spec conclude(map(), term(), map(), :success | {:failure, term()}) :: map()
  defp conclude(state, name, svc, outcome) do
    if svc.task_mon, do: Process.demonitor(svc.task_mon, [:flush])
    now = state.clock.()

    svc =
      case outcome do
        :success -> %{svc | consecutive_failures: 0, status: :up}
        {:failure, reason} -> apply_failure(state, name, svc, reason)
      end

    svc = %{
      svc
      | check_in_flight: false,
        check_ref: nil,
        task_pid: nil,
        task_mon: nil,
        last_check_at: now
    }

    timer = Process.send_after(self(), {:schedule_check, name}, svc.interval_ms)
    update_service(state, name, %{svc | sched_timer: timer})
  end

  @spec apply_failure(map(), term(), map(), term()) :: map()
  defp apply_failure(state, name, svc, reason) do
    new_count = svc.consecutive_failures + 1

    if new_count >= svc.max_failures and svc.status != :down do
      state.notify.(name, reason)
      %{svc | consecutive_failures: new_count, status: :down}
    else
      %{svc | consecutive_failures: new_count}
    end
  end

  @spec outcome_from(term()) :: :success | {:failure, term()}
  defp outcome_from(:ok), do: :success
  defp outcome_from({:error, reason}), do: {:failure, reason}
  defp outcome_from(other), do: {:failure, other}

  @spec cancel_task(map()) :: :ok
  defp cancel_task(svc) do
    if svc.task_pid, do: Process.exit(svc.task_pid, :kill)
    if svc.task_mon, do: Process.demonitor(svc.task_mon, [:flush])
    :ok
  end

  @spec cancel_sched(map()) :: :ok
  defp cancel_sched(svc) do
    if svc.sched_timer, do: Process.cancel_timer(svc.sched_timer)
    :ok
  end

  @spec update_service(map(), term(), map()) :: map()
  defp update_service(state, name, svc) do
    %{state | services: Map.put(state.services, name, svc)}
  end

  @spec build_info(map()) :: map()
  defp build_info(svc) do
    %{
      status: svc.status,
      last_check_at: svc.last_check_at,
      consecutive_failures: svc.consecutive_failures,
      check_in_flight: svc.check_in_flight
    }
  end
end