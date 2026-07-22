  @impl true
  def handle_info({:check, name, generation}, state) do
    case Map.get(state, name) do
      %{generation: ^generation} = service ->
        {updated, _status} = run_check(service, name)
        schedule(name, generation, updated.interval_ms)
        {:noreply, Map.put(state, name, updated)}

      _other ->
        # Unknown service or a superseded generation token: ignore.
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end