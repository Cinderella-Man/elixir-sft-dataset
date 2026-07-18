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
        maintenance_timer: nil
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