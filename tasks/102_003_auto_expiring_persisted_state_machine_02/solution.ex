  @spec apply_transition(String.t(), state(), event(), map()) ::
          {:reply, term(), map()}
  defp apply_transition(entity_id, current, event, state) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            new_states = Map.put(state.states, entity_id, next)
            {:reply, {:ok, next}, %{state | states: new_states}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end