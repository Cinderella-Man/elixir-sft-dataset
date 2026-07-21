# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ManagedMonitor do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opt, gen_opts} =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> {[name: name], []}
        :error -> {[], []}
      end

    GenServer.start_link(__MODULE__, opts, gen_opts ++ name_opt)
  end

  def register(server, service_name, check_func, interval_ms, max_failures \\ 3) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, max_failures})
  end

  def status(server, service_name) do
    GenServer.call(server, {:status, service_name})
  end

  def statuses(server) do
    GenServer.call(server, :statuses)
  end

  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end

  def pause(server, service_name) do
    GenServer.call(server, {:pause, service_name})
  end

  def resume(server, service_name) do
    GenServer.call(server, {:resume, service_name})
  end

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
        check_timer: nil
      }

      service = %{service | check_timer: schedule_check(name, interval_ms)}

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
        # Kill the whole check chain: the armed timer AND any {:check, name}
        # already sitting in the mailbox — the prompt's rule is that the old
        # registration's leftover timers must not drive a re-registration.
        if service.check_timer, do: Process.cancel_timer(service.check_timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

      :error ->
        :ok
    end

    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end

  def handle_call({:pause, name}, _from, state) do
    case Map.fetch(state.services, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, service} ->
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
        # leftover timer (same resurrection class as deregister's — see
        # handle_call({:deregister, ...})).
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
        # would end at the OLD deadline with a spurious :maintenance_ended
        # (probe-proven 2026-07-15). Cancel the tracked timer AND drain an
        # already-queued expiry before arming the new one.
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

      {:ok, %{mode: :paused} = service} ->
        # Paused: skip the check but keep scheduling (one chain, fresh ref).
        service = rearm(service, name)
        {:noreply, put_in(state.services[name], service)}

      {:ok, %{mode: :maintenance} = service} ->
        now = state.clock.()
        result = service.check_func.()

        new_service = rearm(apply_maintenance_check(service, result, now), name)

        {:noreply, put_in(state.services[name], new_service)}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, events} = apply_active_check(service, result, now)
        new_service = rearm(new_service, name)

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

  # Active mode check: normal failure counting and status transitions.
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
  # sent — the same argument as deregister's drain).
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

  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end

  # One chain per service, always: cancel whatever is armed before arming the
  # next timer, so neither a manual {:check, name} trigger nor a stale chain
  # can multiply the check rate.
  defp rearm(service, name) do
    if service.check_timer, do: Process.cancel_timer(service.check_timer)
    %{service | check_timer: schedule_check(name, service.interval_ms)}
  end

  # Compute the reported status from the internal health + mode.
  defp reported_status(%{mode: :paused}), do: :paused
  defp reported_status(%{mode: :maintenance}), do: :maintenance
  defp reported_status(%{health: health}), do: health

  defp to_status_info(service) do
    %{
      status: reported_status(service),
      last_check_at: service.last_check_at,
      consecutive_failures: service.consecutive_failures,
      maintenance_ends_at: service.maintenance_ends_at
    }
  end

  defp fire_notify(nil, _name, _event, _detail), do: :ok
  defp fire_notify(notify_fn, name, event, detail), do: notify_fn.(name, event, detail)
end
```
