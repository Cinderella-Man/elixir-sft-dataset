defmodule AsyncMonitor do
  @moduledoc """
  A `GenServer` that supervises registered services by running each service's
  health check **asynchronously** in a spawned, monitored `Task` with a
  per-service timeout.

  Because every check runs in its own short-lived process, a slow or hung check
  can never block the monitor itself or the checks of other services. The
  monitor communicates with its check Tasks through a small, documented message
  protocol (`:schedule_check`, `:check_result`, `:check_timeout`) so that tests
  can drive and observe behaviour deterministically.

  Each registered service carries its own independent state: a status
  (`:pending`, `:up` or `:down`), a running count of consecutive failures, the
  time of its most recent concluded check and whether a check is currently in
  flight. A service is marked `:down` after `:max_failures` consecutive
  failures (timeouts count as failures), at which point an optional `:notify`
  callback is invoked exactly once. Recovering to `:ok` re-arms that
  notification.

  Only OTP standard-library facilities are used.
  """

  use GenServer

  @type server :: GenServer.server()

  @type service_name :: term()

  @type check_result :: :ok | {:error, term()}

  @type check_func :: (-> check_result())

  @type status :: :pending | :up | :down

  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          check_in_flight: boolean()
        }

  @default_max_failures 3
  @default_timeout_ms 5000

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts and links the monitor process.

  `opts` may contain:

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — a two-arity function `notify.(service_name, reason)` invoked
      once when a service transitions to `:down`. Defaults to a no-op.

  Returns the usual `GenServer.on_start()` result.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @doc """
  Registers `service_name` with a zero-arity `check_func` to be run every
  `interval_ms` milliseconds.

  `opts` may contain `:max_failures` (default `3`) and `:timeout_ms`
  (default `5000`).

  Returns `:ok`, or `{:error, :already_registered}` if the name is already
  registered. An existing registration is never replaced or altered.
  """
  @spec register(server(), service_name(), check_func(), non_neg_integer(), keyword()) ::
          :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end

  @doc """
  Removes `service_name` from monitoring, shutting down any in-flight check and
  neutralising the registration's leftover scheduled messages.

  Always returns `:ok`, whether or not the service was registered.
  Deregistration is final for that registration.
  """
  @spec deregister(server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Returns `{:ok, status_info}` for a registered service, or
  `{:error, :not_found}` otherwise.
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

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)
    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl true
  def handle_call({:register, name, func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      svc = %{
        check_func: func,
        interval_ms: interval_ms,
        max_failures: Keyword.get(opts, :max_failures, @default_max_failures),
        timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
        status: :pending,
        consecutive_failures: 0,
        last_check_at: nil,
        check_in_flight: false,
        expected_ref: nil,
        task_pid: nil,
        task_mon: nil
      }

      Process.send_after(self(), {:schedule_check, name}, interval_ms)
      {:reply, :ok, put_service(state, name, svc)}
    end
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, svc} ->
        shutdown_task(svc)
        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, svc} -> {:reply, {:ok, info(svc)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, info(svc)} end)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:schedule_check, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{check_in_flight: true}} -> {:noreply, state}
      {:ok, svc} -> {:noreply, start_check(state, name, svc)}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:check_result, name, ref, result}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{expected_ref: ^ref} = svc} ->
        {:noreply, conclude(state, name, svc, outcome(result))}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:check_timeout, name, ref}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{expected_ref: ^ref} = svc} ->
        if svc.task_pid, do: Process.exit(svc.task_pid, :kill)
        {:noreply, conclude(state, name, svc, {:fail, :timeout})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  @spec start_check(map(), service_name(), map()) :: map()
  defp start_check(state, name, svc) do
    server = self()
    ref = make_ref()
    func = svc.check_func

    {pid, mon} =
      spawn_monitor(fn ->
        result = func.()
        send(server, {:check_result, name, ref, result})
      end)

    Process.send_after(server, {:check_timeout, name, ref}, svc.timeout_ms)

    new_svc = %{
      svc
      | check_in_flight: true,
        expected_ref: ref,
        task_pid: pid,
        task_mon: mon
    }

    put_service(state, name, new_svc)
  end

  @spec conclude(map(), service_name(), map(), :ok | {:fail, term()}) :: map()
  defp conclude(state, name, svc, outcome) do
    if svc.task_mon, do: Process.demonitor(svc.task_mon, [:flush])
    now = state.clock.()
    {updated, notify?, reason} = apply_outcome(svc, outcome)

    updated = %{
      updated
      | check_in_flight: false,
        expected_ref: nil,
        task_pid: nil,
        task_mon: nil,
        last_check_at: now
    }

    Process.send_after(self(), {:schedule_check, name}, svc.interval_ms)
    if notify?, do: state.notify.(name, reason)
    put_service(state, name, updated)
  end

  @spec apply_outcome(map(), :ok | {:fail, term()}) :: {map(), boolean(), term()}
  defp apply_outcome(svc, :ok) do
    {%{svc | status: :up, consecutive_failures: 0}, false, nil}
  end

  defp apply_outcome(svc, {:fail, reason}) do
    failures = svc.consecutive_failures + 1

    cond do
      failures >= svc.max_failures and svc.status != :down ->
        {%{svc | status: :down, consecutive_failures: failures}, true, reason}

      true ->
        {%{svc | consecutive_failures: failures}, false, reason}
    end
  end

  @spec outcome(check_result()) :: :ok | {:fail, term()}
  defp outcome(:ok), do: :ok
  defp outcome({:error, reason}), do: {:fail, reason}
  defp outcome(other), do: {:fail, other}

  @spec shutdown_task(map()) :: :ok
  defp shutdown_task(svc) do
    if svc.task_pid, do: Process.exit(svc.task_pid, :kill)
    if svc.task_mon, do: Process.demonitor(svc.task_mon, [:flush])
    :ok
  end

  @spec put_service(map(), service_name(), map()) :: map()
  defp put_service(state, name, svc) do
    %{state | services: Map.put(state.services, name, svc)}
  end

  @spec info(map()) :: status_info()
  defp info(svc) do
    %{
      status: svc.status,
      last_check_at: svc.last_check_at,
      consecutive_failures: svc.consecutive_failures,
      check_in_flight: svc.check_in_flight
    }
  end
end