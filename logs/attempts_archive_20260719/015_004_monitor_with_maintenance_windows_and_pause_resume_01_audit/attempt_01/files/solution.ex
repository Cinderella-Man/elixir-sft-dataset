defmodule ManagedMonitor do
  @moduledoc """
  A GenServer that monitors registered services via periodic heartbeat checks
  with support for maintenance windows and manual pause/resume.

  Services can be paused (checks skipped entirely) or placed in maintenance
  mode (checks run but failures are suppressed). Maintenance windows
  auto-expire after a configured duration.

  Every timer this module arms is tracked on the service it belongs to, so a
  `deregister/2` (or a replaced maintenance window) can retire it: the message
  shapes `{:check, name}` and `{:maintenance_end, name}` are part of the public
  contract and carry no generation marker, so a leftover timer would otherwise
  be indistinguishable from a live one and could drive a later registration.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type service_name :: term()
  @type status :: :pending | :up | :down | :paused | :maintenance
  @type status_info :: %{
          status: status(),
          last_check_at: integer() | nil,
          consecutive_failures: non_neg_integer(),
          maintenance_ends_at: integer() | nil
        }

  @typep mode :: :active | :paused | :maintenance
  @typep health :: :pending | :up | :down

  @typep service :: %{
           check_func: (-> :ok | {:error, term()}),
           interval_ms: pos_integer(),
           max_failures: pos_integer(),
           health: health(),
           mode: mode(),
           last_check_at: integer() | nil,
           consecutive_failures: non_neg_integer(),
           notified_down: boolean(),
           maintenance_ends_at: integer() | nil,
           maintenance_timer: reference() | nil,
           check_timer: reference() | nil
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts and links the monitor. Accepts `:clock`, `:notify` and `:name` options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name_opt =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, opts, name_opt)
  end

  @doc "Registers `service_name` with `check_func` every `interval_ms`. Returns `:ok`."
  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          pos_integer()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, max_failures \\ 3) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  @doc "Returns `{:ok, status_info}` for a registered service, `{:error, :not_found}` otherwise."
  @spec status(GenServer.server(), service_name()) ::
          {:ok, status_info()} | {:error, :not_found}
  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  @doc "Returns a map of every registered service name to its status info map."
  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  @doc "Removes a service and retires its timers. Always returns `:ok`."
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  @doc "Pauses monitoring: timers keep firing but the check function is not executed."
  @spec pause(GenServer.server(), service_name()) :: :ok | {:error, :not_found}
  def pause(server, service_name) do
    GenServer.call(server, {:pause, service_name})
  end

  @doc "Resumes a paused or in-maintenance service, restoring its underlying health."
  @spec resume(GenServer.server(), service_name()) ::
          :ok | {:error, :not_found} | {:error, :not_paused}
  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end

  @doc "Puts a service into a maintenance window for `duration_ms` milliseconds."
  @spec maintenance(GenServer.server(), service_name(), pos_integer()) ::
          :ok | {:error, :not_found}
  def maintenance(server, service_name, duration_ms) do
    GenServer.call(server, {:maintenance, service_name, duration_ms})
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
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        maintenance_ends_at: nil,
        maintenance_timer: nil,
        check_timer: schedule_check(name, interval_ms)
      }

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
      :error ->
        {:reply, :ok, state}

      {:ok, service} ->
        # Both of this registration's timers must be retired here. The wire
        # messages carry only the service name, so a surviving timer would be
        # accepted verbatim by a LATER registration of the same name: a stale
        # {:check, name} would run the new check_func, and a stale
        # {:maintenance_end, name} would close the new window early.
        service
        |> cancel_maintenance_timer(name)
        |> cancel_check_timer(name)

        {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
    end
  end

  def handle_call({:pause, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        service = cancel_maintenance_timer(service, name)
        new_service = %{service | mode: :paused, maintenance_ends_at: nil}
        {:reply, :ok, put_in(state.services[name], new_service)}
    end
  end

  def handle_call({:resume, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{mode: mode} = service} when mode in [:paused, :maintenance] ->
        # A manual resume from maintenance must kill the pending expiry, or a
        # LATER maintenance session would be ended early by this session's
        # leftover timer (same resurrection class as deregister's).
        service = cancel_maintenance_timer(service, name)
        new_service = %{service | mode: :active, maintenance_ends_at: nil}
        {:reply, :ok, put_in(state.services[name], new_service)}

      {:ok, _service} ->
        {:reply, {:error, :not_paused}, state}
    end
  end

  def handle_call({:maintenance, name, duration_ms}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
        now = state.clock.()
        ends_at = now + duration_ms

        # Re-entering maintenance REPLACES the duration: the previous session's
        # expiry must never fire, or extending a window (say 100ms -> 10s)
        # would end at the OLD deadline with a spurious :maintenance_ended.
        service = cancel_maintenance_timer(service, name)
        timer = Process.send_after(self(), {:maintenance_end, name}, duration_ms)

        new_service = %{
          service
          | mode: :maintenance,
            maintenance_ends_at: ends_at,
            maintenance_timer: timer
        }

        new_state = put_in(state.services[name], new_service)

        fire_notify(state.notify, name, :maintenance_started, duration_ms)

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:noreply, state}

      {:ok, service} ->
        {checked, events} = run_check(service, state.clock)

        # The timer keeps firing every interval_ms regardless of mode.
        new_service = %{checked | check_timer: schedule_check(name, service.interval_ms)}
        new_state = put_in(state.services[name], new_service)

        for {event, detail} <- events do
          fire_notify(state.notify, name, event, detail)
        end

        {:noreply, new_state}
    end
  end

  def handle_info({:maintenance_end, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard.
        {:noreply, state}

      {:ok, %{mode: :maintenance} = service} ->
        new_service = %{service | mode: :active, maintenance_ends_at: nil, maintenance_timer: nil}

        fire_notify(state.notify, name, :maintenance_ended, nil)

        {:noreply, put_in(state.services[name], new_service)}

      {:ok, _service} ->
        # Service is no longer in maintenance (e.g., was resumed manually).
        # Stale timer — discard.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Runs one check cycle with the mode-dependent semantics.
  @spec run_check(service(), (-> integer())) :: {service(), list({atom(), term()})}
  defp run_check(%{mode: :paused} = service, _clock), do: {service, []}

  defp run_check(%{mode: :maintenance} = service, clock) do
    now = clock.()
    result = service.check_func.()
    {apply_maintenance_check(service, result, now), []}
  end

  defp run_check(service, clock) do
    now = clock.()
    result = service.check_func.()
    apply_active_check(service, result, now)
  end

  # Active mode check: normal failure counting and status transitions.
  @spec apply_active_check(service(), :ok | {:error, term()}, integer()) ::
          {service(), list({atom(), term()})}
  defp apply_active_check(service, :ok, now) do
    was_down = service.health == :down

    new_service = %{
      service
      | health: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }

    events = if was_down, do: [{:recovered, nil}], else: []

    {new_service, events}
  end

  defp apply_active_check(service, {:error, reason}, now) do
    new_failures = service.consecutive_failures + 1
    threshold_reached = new_failures >= service.max_failures

    notify? = threshold_reached && !service.notified_down

    new_health = if threshold_reached, do: :down, else: service.health

    new_service = %{
      service
      | health: new_health,
        last_check_at: now,
        consecutive_failures: new_failures,
        notified_down: service.notified_down || notify?
    }

    events = if notify?, do: [{:down, reason}], else: []

    {new_service, events}
  end

  # Maintenance mode check: successes update health, failures are suppressed.
  @spec apply_maintenance_check(service(), :ok | {:error, term()}, integer()) :: service()
  defp apply_maintenance_check(service, :ok, now) do
    %{
      service
      | health: :up,
        last_check_at: now,
        consecutive_failures: 0,
        notified_down: false
    }
  end

  defp apply_maintenance_check(service, {:error, _reason}, now) do
    # Failures during maintenance are observed (last_check_at updates) but
    # do NOT increment the failure counter or trigger :down.
    %{service | last_check_at: now}
  end

  # Cancel a service's pending maintenance-expiry timer AND drain an
  # already-queued {:maintenance_end, name} for it. Cancelling alone is not
  # enough: a timer that fired before the cancel has its message queued BEHIND
  # the current call, and it would end the wrong (newer) maintenance session
  # (`after 0` cannot block: the message is either queued by now or was never
  # sent).
  @spec cancel_maintenance_timer(service(), service_name()) :: service()
  defp cancel_maintenance_timer(%{maintenance_timer: nil} = service, _name), do: service

  defp cancel_maintenance_timer(%{maintenance_timer: timer} = service, name) do
    Process.cancel_timer(timer)

    receive do
      {:maintenance_end, ^name} -> :ok
    after
      0 -> :ok
    end

    %{service | maintenance_timer: nil}
  end

  # Same drain argument as above, for the periodic check timer: a fired-but-
  # queued {:check, name} would otherwise be picked up by a re-registration of
  # the same name and run the NEW check function on the OLD schedule.
  @spec cancel_check_timer(service(), service_name()) :: service()
  defp cancel_check_timer(%{check_timer: nil} = service, _name), do: service

  defp cancel_check_timer(%{check_timer: timer} = service, name) do
    Process.cancel_timer(timer)

    receive do
      {:check, ^name} -> :ok
    after
      0 -> :ok
    end

    %{service | check_timer: nil}
  end

  @spec schedule_check(service_name(), pos_integer()) :: reference()
  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  # Compute the reported status from the internal health + mode.
  @spec reported_status(service()) :: status()
  defp reported_status(%{mode: :paused}), do: :paused
  defp reported_status(%{mode: :maintenance}), do: :maintenance
  defp reported_status(%{health: health}), do: health

  @spec to_status_info(service()) :: status_info()
  defp to_status_info(service) do
    %{
      status: reported_status(service),
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at
    }
  end

  @spec fire_notify(
          (service_name(), atom(), term() -> any()) | nil,
          service_name(),
          atom(),
          term()
        ) :: any()
  defp fire_notify(nil, _name, _event, _detail), do: :ok
  defp fire_notify(notify_fn, name, event, detail), do: notify_fn.(name, event, detail)
end
