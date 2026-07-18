  defp do_transition(entity_id, event, current_state, approvals, state) do
    case next_state(current_state, event, approvals, state.required) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, new_state, new_approvals} ->
        persist(entity_id, event, current_state, new_state, new_approvals, state)
    end
  end