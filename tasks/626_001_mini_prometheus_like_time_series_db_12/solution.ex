  defp chunk_start_for(timestamp, chunk_duration_ms) do
    div(timestamp, chunk_duration_ms) * chunk_duration_ms
  end