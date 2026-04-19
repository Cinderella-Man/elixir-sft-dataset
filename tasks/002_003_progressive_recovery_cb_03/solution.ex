defp execute_in_half_open(state, func) do
  case execute_and_classify(func) do
    {:ok, reply} ->
      # Probe cleared — begin staged recovery from stage 0.
      {reply,
        %{
          state
          | state: :recovering,
            recovery_stage: 0,
            stage_calls: 0,
            stage_failures: 0,
            probes_in_flight: 0,
            opened_at: nil,
            failure_count: 0
        }}

    {:error, reply} ->
      {reply,
        %{state | state: :open, opened_at: state.clock.(), probes_in_flight: 0}}
  end
end
