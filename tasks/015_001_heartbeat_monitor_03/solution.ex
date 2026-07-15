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

        # Schedule the next check before updating state so the cadence is
        # maintained even if the check itself took a while; the fresh ref
        # replaces the fired one so deregister always cancels the live timer.
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

  # Catch-all — ignore unexpected messages.
  def handle_info(_msg, state), do: {:noreply, state}