  defp commit(state, entity_id, event, from_state, to_state, new_version) do
    case persist(state.repo, entity_id, event, from_state, to_state, new_version) do
      {:ok, _record} ->
        entities = Map.put(state.entities, entity_id, {to_state, new_version})
        {:reply, {:ok, to_state, new_version}, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end