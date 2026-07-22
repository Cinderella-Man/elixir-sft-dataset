  defp cleanup(state) do
    now = state.clock.()
    threshold = now - state.retention_ms

    new_series =
      state.series
      |> Enum.map(fn {key, entry} ->
        kept =
          entry.chunks
          |> Enum.reject(fn {chunk_start, _points} ->
            chunk_start + state.chunk_duration_ms <= threshold
          end)
          |> Map.new()

        {key, %{entry | chunks: kept}}
      end)
      |> Enum.reject(fn {_key, entry} -> map_size(entry.chunks) == 0 end)
      |> Map.new()

    %{state | series: new_series}
  end