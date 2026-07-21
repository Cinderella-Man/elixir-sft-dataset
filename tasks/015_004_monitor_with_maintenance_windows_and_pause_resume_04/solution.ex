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
