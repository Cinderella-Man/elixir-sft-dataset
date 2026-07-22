defmodule AsyncMonitor do
  @moduledoc """
  `AsyncMonitor` is a `GenServer` that supervises registered services by running
  each service's health check asynchronously in a spawned, monitored `Task` with
  a per-service timeout.

  Because every check runs in its own process, a slow or hung check can never
  block the monitor or the checks of other services. Each service is tracked
  independently: its consecutive-failure counter, status, and in-flight state are
  isolated from every other service.

  ## Lifecycle of a check

  A service's next check is armed with
  `Process.send_after(self(), {:schedule_check, name}, interval_ms)`. When that
  message is received the monitor spawns a `Task` that runs the check function and
  reports back with `{:check_result, name, ref, result}`. At spawn time a timeout
  is armed with `{:check_timeout, name, ref}`; if it fires while the same check is
  still in flight the `Task` is killed and the check is treated as a `:timeout`
  failure.

  Every `{:check_result, ...}` and `{:check_timeout, ...}` carries a reference
  that must match the service's currently expected reference; stale messages
  (late results, superseded timeouts, or messages belonging to a deregistered or
  re-registered service) are silently discarded.

  Only the OTP standard library is used.
  """

  use GenServer

  @type server :: GenServer.server()
  @type service_name :: term()
  @type check_func :: (-> :ok | {:error, term()})
  @type status_info :: %{
          status: :pending | :up | :down,
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean()
        }

  @default_max_failures 3
  @default_timeout_ms 5_000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts and links the monitor process.

  `opts` may contain:

    * `:clock` — a zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — a two-arity function `notify.(service_name, reason)` invoked when
      a service transitions to `:down`. Defaults to a no-op.

  Returns the usual `GenServer.on_start()` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Registers `service_name` with the monitor.

  `check_func` is a zero-arity function returning `:ok` or `{:error, reason}`.
  `interval_ms` is the delay between that service's checks.

  `opts` may contain:

    * `:max_failures` — consecutive failures (including timeouts) before the
      service is marked `:down`. Defaults to `3`.
    * `:timeout_ms` — the maximum time a single check `Task` may run. Defaults to
      `5000`.

  Returns `:ok`, or `{:error, :already_registered}` if a service with that name is
  already registered. An existing registration is never replaced or altered by a
  second call. The service starts in status `:pending`; the first check is
  scheduled `interval_ms` milliseconds later.
  """
  @spec register(server(), service_name(), check_func(), non_neg_integer(), keyword()) ::
          :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Removes `service_name` from monitoring, always returning `:ok`.

  Deregistration is final for that registration: any in-flight check `Task` is
  shut down, all scheduled messages become inert, and the service no longer
  appears in `statuses/1`. The same name may be registered again afterwards and
  starts fresh in `:pending`.
  """
  @spec deregister(server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service or `{:error, :not_found}`.

  `status_info` contains `:status`, `:last_check_at`, `:consecutive_failures`, and
  `:check_in_flight`.
  """
  @spec status(server(), service_name()) :: {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `status_info` map.
  """
  @spec statuses(server()) :: %{optional(service_name()) => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)
    {:ok, %{services: %{}, clock: clock, notify: notify}}
  end

  @impl true
  def handle_call({:register, name, func, interval, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      max_failures = Keyword.get(opts, :max_failures, @default_max_failures)
      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      timer = Process.send_after(self(), {:schedule_check, name}, interval)

      svc = %{
        check_func: func,
        interval_ms: interval,
        max_failures: max_failures,
        timeout_ms: timeout_ms,
        status: :pending,
        consecutive_failures: 0,
        last_check_at: nil,
        check_in_flight: false,
        expected_ref: nil,
        task_pid: nil,
        schedule_timer: timer,
        timeout_timer: nil
      }

      {:reply, :ok, put_service(state, name, svc)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.pop(state.services, name) do
      {nil, _services} ->
        {:reply, :ok, state}

      {svc, services} ->
        cancel_timer(svc.schedule_timer)
        cancel_timer(svc.timeout_timer)
        if is_pid(svc.task_pid), do: Process.exit(svc.task_pid, :kill)
        {:reply, :ok, %{state | services: services}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.get(state.services, name) do
      nil -> {:reply, {:error, :not_found}, state}
      svc -> {:reply, {:ok, status_info(svc)}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    infos = Map.new(state.services, fn {name, svc} -> {name, status_info(svc)} end)
    {:reply, infos, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :bad_request}, state}
  end

  @impl true
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl true
  def handle_info({:schedule_check, name}, state) do
    case Map.get(state.services, name) do
      %{check_in_flight: false} = svc ->
        {:noreply, start_check(state, name, svc)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    case Map.get(state.services, name) do
      %{expected_ref: ^ref} = svc ->
        {:noreply, conclude_check(state, name, svc, normalize_result(result))}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    case Map.get(state.services, name) do
      %{expected_ref: ^ref, task_pid: pid} = svc ->
        if is_pid(pid), do: Process.exit(pid, :kill)
        {:noreply, conclude_check(state, name, svc, {:failure, :timeout})}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --------------------------------------------------------------------------
  # Internal helpers
  # --------------------------------------------------------------------------

  @spec start_check(map(), service_name(), map()) :: map()
  defp start_check(state, name, svc) do
    server = self()
    ref = make_ref()
    check_func = svc.check_func

    {pid, _monitor_ref} =
      spawn_monitor(fn ->
        result =
          try do
            check_func.()
          catch
            kind, value -> {:error, {kind, value}}
          end

        send(server, {:check_result, name, ref, result})
      end)

    timeout_timer =
      Process.send_after(server, {:check_timeout, name, ref}, svc.timeout_ms)

    svc = %{
      svc
      | check_in_flight: true,
        expected_ref: ref,
        task_pid: pid,
        timeout_timer: timeout_timer,
        schedule_timer: nil
    }

    put_service(state, name, svc)
  end

  @spec normalize_result(term()) :: :ok | {:failure, term()}
  defp normalize_result(:ok), do: :ok
  defp normalize_result({:error, reason}), do: {:failure, reason}
  defp normalize_result(other), do: {:failure, {:invalid_result, other}}

  @spec conclude_check(map(), service_name(), map(), :ok | {:failure, term()}) :: map()
  defp conclude_check(state, name, svc, :ok) do
    now = state.clock.()
    cancel_timer(svc.timeout_timer)

    svc = %{
      svc
      | status: :up,
        consecutive_failures: 0,
        last_check_at: now,
        check_in_flight: false,
        expected_ref: nil,
        task_pid: nil,
        timeout_timer: nil
    }

    put_service(state, name, reschedule(svc, name))
  end

  defp conclude_check(state, name, svc, {:failure, reason}) do
    now = state.clock.()
    cancel_timer(svc.timeout_timer)
    cf = svc.consecutive_failures + 1

    {status, notify?} =
      if cf >= svc.max_failures and svc.status != :down do
        {:down, true}
      else
        {svc.status, false}
      end

    if notify?, do: state.notify.(name, reason)

    svc = %{
      svc
      | status: status,
        consecutive_failures: cf,
        last_check_at: now,
        check_in_flight: false,
        expected_ref: nil,
        task_pid: nil,
        timeout_timer: nil
    }

    put_service(state, name, reschedule(svc, name))
  end

  @spec reschedule(map(), service_name()) :: map()
  defp reschedule(svc, name) do
    timer = Process.send_after(self(), {:schedule_check, name}, svc.interval_ms)
    %{svc | schedule_timer: timer}
  end

  @spec put_service(map(), service_name(), map()) :: map()
  defp put_service(state, name, svc) do
    %{state | services: Map.put(state.services, name, svc)}
  end

  @spec status_info(map()) :: status_info()
  defp status_info(svc) do
    %{
      status: svc.status,
      last_check_at: svc.last_check_at,
      consecutive_failures: svc.consecutive_failures,
      check_in_flight: svc.check_in_flight
    }
  end

  @spec cancel_timer(reference() | nil) :: :ok
  defp cancel_timer(nil), do: :ok

  defp cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end
end