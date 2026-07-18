  @impl true
  def handle_info({:check_expiry, entity_id}, state) do
    case Map.get(state.states, entity_id) do
      :pending ->
        case persist(state.repo, entity_id, :expire, :pending, :cancelled) do
          :ok ->
            new_states = Map.put(state.states, entity_id, :cancelled)
            {:noreply, %{state | states: new_states}}

          {:error, _reason} ->
            {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}