  defp do_query(state, metric_name, label_matchers, start_ts, end_ts) do
    chunk_duration_ms = state.chunk_duration_ms

    # Find the chunk windows that overlap [start_ts, end_ts]
    first_chunk = chunk_start_for(start_ts, chunk_duration_ms)
    last_chunk = chunk_start_for(end_ts, chunk_duration_ms)

    Enum.flat_map(state.series, fn {{m, sorted_labels}, series} ->
      if m != metric_name do
        []
      else
        labels_map = Map.new(sorted_labels)

        if labels_match?(labels_map, label_matchers) do
          # Collect points from all relevant chunks
          points =
            series
            |> Enum.filter(fn {chunk_start, _} ->
              chunk_start >= first_chunk and chunk_start <= last_chunk
            end)
            |> Enum.flat_map(fn {_chunk_start, pts} -> pts end)
            |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
            |> Enum.sort_by(fn {ts, _} -> ts end)

          if points == [] do
            []
          else
            [{labels_map, points}]
          end
        else
          []
        end
      end
    end)
  end