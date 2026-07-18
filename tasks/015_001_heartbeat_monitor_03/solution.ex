  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered after this message was sent; discard it.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        # AT MOST ONE live timer per service, unconditionally: cancel the
        # pending timer before re-arming. For a chain tick this is a no-op
        # (its own timer already fired); for a MANUAL `{:check, name}` it
        # retires the pending chain tick so the manual check resets the
        # cadence instead of arming a second chain whose ref would be lost —
        # an orphan that leaks, double-drives the cadence, and can even
        # resurrect into a later re-registration (F23).
        _ = Process.cancel_timer(service.timer)

        receive do
          {:check, ^name} -> :ok
        after
          0 -> :ok
        end

        timer = schedule_check(name, service.interval_ms)
        new_state = put_in(state.services[name], %{new_service | timer: timer})

        if notify? do
          # Extract the reason from the result we already have.
          {:error, reason} = result
          fire_notify(state.notify, name, reason)
        end

        {:noreply, new_state}
    end
  end