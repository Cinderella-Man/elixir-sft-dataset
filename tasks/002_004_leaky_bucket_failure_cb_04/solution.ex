defp execute_in_half_open(state, func) do
  case execute_and_classify(func) do
    {:ok, reply} ->
      # Probe succeeded — fresh bucket, full closure.
      {reply,
        %{
          state
          | state: :closed,
            bucket_level: 0.0,
            last_update_at: state.clock.(),
            opened_at: nil,
            probes_in_flight: 0
        }}

    {:error, reply} ->
      {reply,
        %{state | state: :open, opened_at: state.clock.(), probes_in_flight: 0}}
  end
end
