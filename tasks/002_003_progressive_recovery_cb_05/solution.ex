defp advance_stage(state, reply) do
  next_stage = state.recovery_stage + 1

  if next_stage >= length(state.config.recovery_stages) do
    # Final stage cleared → full closure.
    {reply,
      %{
        state
        | state: :closed,
          recovery_stage: 0,
          stage_calls: 0,
          stage_failures: 0,
          failure_count: 0
      }}
  else
    # Move to next stage with fresh counters.
    {reply,
      %{state | recovery_stage: next_stage, stage_calls: 0, stage_failures: 0}}
  end
end
