  defp do_transition(state, entity_id, event, expected_version, cur_state, cur_version) do
    cond do
      expected_version != cur_version ->
        {:reply, {:error, {:stale_version, cur_version}}, state}

      not Map.has_key?(@transitions, {cur_state, event}) ->
        {:reply, {:error, :invalid_transition}, state}

      true ->
        next_state = Map.fetch!(@transitions, {cur_state, event})
        new_version = cur_version + 1
        commit(state, entity_id, event, cur_state, next_state, new_version)
    end
  end