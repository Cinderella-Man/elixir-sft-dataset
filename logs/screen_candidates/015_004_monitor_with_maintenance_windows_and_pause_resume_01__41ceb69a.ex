defmodule ManagedMonitor do
  @moduledoc """
  A `GenServer` that monitors registered services with periodic heartbeat checks.

  Each registered service is associated with a zero-arity check function returning
  `:ok` or `{:error, reason}`. The check runs inside the monitor process every
  `interval_ms` milliseconds, scheduled with tagged `Process.send_after/3` messages
  of the form `{:check, service_name}`.

  Beyond plain health tracking, services support two administrative modes:

    * **paused** — the check timer keeps firing but the check function is *not*
      executed. The underlying health state (`:pending`, `:up` or `:down`) and the
      consecutive failure counter are frozen, and the reported status is `:paused`.
      Calling `resume/2` reverts the reported status to the frozen health state.

    * **maintenance** — the check timer fires and the check function *is* executed,
      but failures neither increment the consecutive failure counter nor cause a
      `:down` transition. Successes still reset the counter and mark the service
      healthy. The reported status is `:maintenance` until the maintenance window
      expires (tracked with a `{:maintenance_end, service_name}` message), after
      which the reported status reverts to the current health state.

  A service is considered `:down` once `max_failures` consecutive failing checks
  have been observed. The `:notify` callback — a function of the form
  `fn service_name, event, detail -> ... end` — is invoked for these events:

    * `(:down, reason)` — exactly once per down-transition (re-armed on recovery);
    * `(:recovered, nil)` — when a service transitions from `:down` back to `:up`;
    * `(:maintenance_started, duration_ms)` — when a maintenance window starts;
    * `(:maintenance_ended, nil)` — when a maintenance window expires.

  Time is read through a `:clock` function (zero-arity, milliseconds), which makes
  the module easy to test with a controllable clock.
  """

  use GenServer

  @type service_name :: term()
  @type check_func :: (-> :ok | {:error, term()})
  @type health :: :pending | :up | :down
  @type status :: :up | :down | :pending | :paused | :maintenance
  @type event :: :down | :recovered | :maintenance_started | :maintenance_ended
  @type notify_func :: (service_name(), event(), term() -> any())
  @type clock :: (-> integer())
  @type status_info :: %{
          status: status(),
          health: health(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          maintenance_ends_at: integer() | nil,
          interval_ms: pos_integer(),
          max_failures: pos_integer()
        }
  @type server :: GenServer.server()

  @default_max_failures 3

  # -- Public API ------------------------------------------------------------

  @doc """
  Starts the monitor process.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:notify` — `fn service_name, event, detail -> ... end` invoked on status
      transitions. Defaults to a no-op.
    * `:name` — optional name used for process registration.

  Any other option is ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Registers `service_name` for monitoring.

  `check_func` is a zero-arity function returning `:ok` or `{:error, reason}`, run
  every `interval_ms` milliseconds. After `max_failures` consecutive failures the
  service is marked `:down`.

  Returns `:ok`, or `{:error, :already_registered}` when the name is already taken.
  """
  @spec register(server(), service_name(), check_func(), pos_integer(), pos_integer()) ::
          :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ @default_max_failures)
      when is_function(check_func, 0) and is_integer(interval_ms) and interval_ms > 0 and
             is_integer(max_failures) and max_failures > 0 do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @doc """
  Returns `{:ok, status_info}` for `service_name`, or `{:error, :not_found}`.

  The status info map contains at least `:status`, `:last_check_at`,
  `:consecutive_failures` and `:maintenance_ends_at`.
  """
  @spec status(server(), service_name()) :: {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc """
  Returns a map of every registered service name to its `t:status_info/0` map.
  """
  @spec statuses(server()) :: %{optional(service_name()) => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc """
  Removes `service_name` from monitoring and cancels its scheduled timers.

  Always returns `:ok`, whether or not the service was registered.
  """
  @spec deregister(server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc """
  Pauses monitoring of `service_name`.

  Check timers keep firing but the check function is not executed; the health state
  and failure counter are frozen and the reported status becomes `:paused`.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec pause(server(), service_name()) :: :ok | {:error, :not_found}
  def pause(server, service_name) do
    GenServer.call(server, {:pause, service_name})
  end

  @doc """
  Resumes a paused service, reverting its reported status to the frozen health
  state (`:pending`, `:up` or `:down`). The failure counter is preserved.

  Returns `:ok`, `{:error, :not_found}`, or `{:error, :not_paused}` when the
  service is not currently paused.
  """
  @spec resume(server(), service_name()) :: :ok | {:error, :not_found} | {:error, :not_paused}
  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end

  @doc """
  Puts `service_name` into maintenance mode for `duration_ms` milliseconds.

  Checks keep running, but failures do not increment the failure counter nor cause
  a `:down` transition; successes still reset the counter and mark the service
  healthy. When the window expires the service resumes normal monitoring.

  Calling this while already in maintenance replaces (restarts) the duration.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec maintenance(server(), service_name(), pos_integer()) :: :ok | {:error, :not_found}
  def maintenance(server, service_name, duration_ms)
      when is_integer(duration_ms) and duration_ms > 0 do
    GenServer.call(server, {:maintenance, service_name, duration_ms})
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    notify = Keyword.get(opts, :notify, fn _name, _event, _detail -> :ok end)

    {:ok, %{clock: clock, notify: notify, services: %{}}}
  end

  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        health: :pending,
        mode: :active,
        consecutive_failures: 0,
        last_check_at: nil,
        maintenance_ends_at: nil,
        check_timer: schedule_check(name, interval_ms),
        maintenance_timer: nil
      }

      {:reply, :ok, put_service(state, name, service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    statuses = Map.new(state.services, fn {name, service} -> {name, status_info(service)} end)
    {:reply, statuses, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        cancel_timer(service.check_timer)
        cancel_timer(service.maintenance_timer)
        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:pause, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        cancel_timer(service.maintenance_timer)

        service = %{
          service
          | mode: :paused,
            maintenance_timer: nil,
            maintenance_ends_at: nil
        }

        {:reply, :ok, put_service(state, name, service)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:resume, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{mode: :paused} = service} ->
        {:reply, :ok, put_service(state, name, %{service | mode: :active})}

      {:ok, _service} ->
        {:reply, {:error, :not_paused}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:maintenance, name, duration_ms}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        cancel_timer(service.maintenance_timer)
        timer = Process.send_after(self(), {:maintenance_end, name}, duration_ms)

        service = %{
          service
          | mode: :maintenance,
            maintenance_timer: timer,
            maintenance_ends_at: state.clock.() + duration_ms
        }

        notify(state, name, :maintenance_started, duration_ms)
        {:reply, :ok, put_service(state, name, service)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} ->
        service = run_check(state, name, service)
        service = %{service | check_timer: schedule_check(name, service.interval_ms)}
        {:noreply, put_service(state, name, service)}

      :error ->
        # Deregistered service: the pending check message has no effect.
        {:noreply, state}
    end
  end

  def handle_info({:maintenance_end, name}, state) do
    case Map.fetch(state.services, name) do
      {:ok, %{mode: :maintenance} = service} ->
        service = %{service | mode: :active, maintenance_timer: nil, maintenance_ends_at: nil}
        notify(state, name, :maintenance_ended, nil)
        {:noreply, put_service(state, name, service)}

      {:ok, _service} ->
        # Maintenance was cancelled or replaced; the stale message is discarded.
        {:noreply, state}

      :error ->
        # Orphaned timer for a deregistered service.
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internal helpers ------------------------------------------------------

  defp run_check(_state, _name, %{mode: :paused} = service), do: service

  defp run_check(state, name, service) do
    now = state.clock.()

    case service.check_func.() do
      :ok -> handle_success(state, name, service, now)
      {:error, reason} -> handle_failure(state, name, service, now, reason)
      _other -> handle_failure(state, name, service, now, :invalid_check_result)
    end
  end

  defp handle_success(state, name, service, now) do
    if service.health == :down do
      notify(state, name, :recovered, nil)
    end

    %{service | health: :up, consecutive_failures: 0, last_check_at: now}
  end

  defp handle_failure(_state, _name, %{mode: :maintenance} = service, now, _reason) do
    %{service | last_check_at: now}
  end

  defp handle_failure(state, name, service, now, reason) do
    failures = service.consecutive_failures + 1
    service = %{service | consecutive_failures: failures, last_check_at: now}

    if failures >= service.max_failures and service.health != :down do
      notify(state, name, :down, reason)
      %{service | health: :down}
    else
      service
    end
  end

  defp status_info(service) do
    %{
      status: reported_status(service),
      health: service.health,
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at,
      interval_ms: service.interval_ms,
      max_failures: service.max_failures
    }
  end

  defp reported_status(%{mode: :paused}), do: :paused
  defp reported_status(%{mode: :maintenance}), do: :maintenance
  defp reported_status(%{health: health}), do: health

  defp put_service(state, name, service) do
    %{state | services: Map.put(state.services, name, service)}
  end

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp notify(state, name, event, detail) do
    state.notify.(name, event, detail)
    :ok
  end
end