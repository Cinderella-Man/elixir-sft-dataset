  defp reset_state(state) do
    %{
      state
      | state: :closed,
        failure_count: 0,
        opened_at: nil,
        probes_in_flight: 0,
        recovery_stage: 0,
        stage_calls: 0,
        stage_failures: 0
    }
  end