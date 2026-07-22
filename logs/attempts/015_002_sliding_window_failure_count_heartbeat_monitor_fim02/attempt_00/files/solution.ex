  @impl true
  def handle_info({:tick, name, epoch}, state) do
    case Map.get(state.services, name) do
      %{epoch: ^epoch, interval: interval} = service when is_integer(interval) ->
        {new_service, _status} = probe_and_notify(name, service)
        maybe_schedule(name, interval, epoch)
        services = Map.put(state.services, name, new_service)
        {:noreply, %{state | services: services}}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end