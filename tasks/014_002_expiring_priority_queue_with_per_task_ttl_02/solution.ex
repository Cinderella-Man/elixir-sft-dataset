  # Pops entries from the queues in priority order, skipping expired ones.
  # Returns {:ok, task, updated_state} or {:empty, updated_state}.
  defp pop_next_valid(state) do
    case pop_highest(state.queues) do
      {nil, _queues} ->
        {:empty, state}

      {{task, expires_at}, queues, priority} ->
        now = state.clock.()
        state = %{state | queues: queues}

        if expires_at <= now do
          # Task has expired — record it and try the next one
          state = %{state | expired: [{task, priority} | state.expired]}
          pop_next_valid(state)
        else
          {:ok, task, state}
        end
    end
  end