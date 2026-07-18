  defp do_cleanup(state) do
    now = state.clock.()
    cutoff = now - state.retention_ms
    chunk_duration_ms = state.chunk_duration_ms

    new_series =
      state.series
      |> Enum.reduce(%{}, fn {series_key, series}, acc ->
        trimmed =
          series
          |> Enum.reject(fn {chunk_start, _} ->
            # A chunk is expired when its end (chunk_start + chunk_duration_ms) <= cutoff
            chunk_start + chunk_duration_ms <= cutoff
          end)
          |> Map.new()

        if map_size(trimmed) == 0 do
          acc
        else
          Map.put(acc, series_key, trimmed)
        end
      end)

    %{state | series: new_series}
  end