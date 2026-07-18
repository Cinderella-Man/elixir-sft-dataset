  defp trip_open(state) do
    %{state | circuit_state: :open, opened_at: state.clock.(), failure_count: 0, probe_count: 0}
  end