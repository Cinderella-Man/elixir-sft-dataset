defp persist(entity_id, event, from_state, to_state, approvals, state) do
  record = %EntityTransition{
    entity_id: entity_id,
    event: Atom.to_string(event),
    from_state: Atom.to_string(from_state),
    to_state: Atom.to_string(to_state),
    approvals: approvals,
    inserted_at: DateTime.utc_now()
  }

  case state.repo.insert(record) do
    {:ok, _row} ->
      entities = Map.put(state.entities, entity_id, {to_state, approvals})
      {:reply, {:ok, to_state, approvals}, %{state | entities: entities}}

    {:error, reason} ->
      {:reply, {:error, {:db_error, reason}}, state}
  end
end