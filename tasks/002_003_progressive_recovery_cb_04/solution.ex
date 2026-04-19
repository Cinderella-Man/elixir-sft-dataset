defp execute_in_recovering(state, func) do
  {outcome, reply} = execute_and_classify(func)

  # 1. Calculate updated counters based on the latest call
  new_stage_calls = state.stage_calls + 1
  new_stage_failures =
    case outcome do
      :error -> state.stage_failures + 1
      :ok -> state.stage_failures
    end

  # 2. Extract limits once using pattern matching
  {required_calls, tolerated_failures} =
    Enum.at(state.config.recovery_stages, state.recovery_stage)

  # 3. Create a temporary state that reflects the current progress
  # This ensures any delegation (like advance_stage) has the "truth"
  updated_state = %{state | stage_calls: new_stage_calls, stage_failures: new_stage_failures}

  cond do
    # Scenario A: Failure limit exceeded -> Crash back to :open
    new_stage_failures > tolerated_failures ->
      new_state = %{
        updated_state # Start with updated counts, then override for :open
        | state: :open,
          opened_at: state.clock.(),
          recovery_stage: 0,
          stage_calls: 0,
          stage_failures: 0
      }
      {reply, new_state}

    # Scenario B: Target reached -> Try to move to next stage or close
    new_stage_calls >= required_calls ->
      advance_stage(updated_state, reply)

    # Scenario C: Progressing -> Stay in :recovering with new counts
    true ->
      {reply, updated_state}
  end
end
