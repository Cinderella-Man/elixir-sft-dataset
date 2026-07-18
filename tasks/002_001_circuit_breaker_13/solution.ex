  defp reset_to_closed(state) do
    %{state | circuit_state: :closed, failure_count: 0, opened_at: nil, probe_count: 0}
  end