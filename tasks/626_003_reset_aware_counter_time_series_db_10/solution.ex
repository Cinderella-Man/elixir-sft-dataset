  @impl true
  def handle_call({:insert, metric, labels, ts, value}, _from, state) do
    key = series_key(metric, labels)
    chunk_start = div(ts, state.chunk_duration_ms) * state.chunk_duration_ms

    entry = Map.get(state.series, key, %{labels: labels, chunks: %{}})
    chunk = Map.get(entry.chunks, chunk_start, [])
    chunk = insert_by_ts(chunk, ts, {ts, value})
    entry = %{entry | chunks: Map.put(entry.chunks, chunk_start, chunk)}

    {:reply, :ok, %{state | series: Map.put(state.series, key, entry)}}
  end

  def handle_call({:query, metric, matchers, range}, _from, state) do
    {start_ts, end_ts} = range

    result =
      state
      |> matching_series(metric, matchers)
      |> Enum.map(fn entry ->
        points =
          entry
          |> series_points()
          |> Enum.filter(fn {ts, _v} -> ts >= start_ts and ts <= end_ts end)

        {entry.labels, points}
      end)
      |> Enum.reject(fn {_labels, points} -> points == [] end)

    {:reply, result, state}
  end

  def handle_call({:query_range, metric, matchers, range, fun, step}, _from, state) do
    {start_ts, end_ts} = range
    wins = windows(start_ts, end_ts, step)

    result =
      state
      |> matching_series(metric, matchers)
      |> Enum.map(fn entry ->
        all_points = series_points(entry)

        range_points =
          Enum.flat_map(wins, fn window_start ->
            window_end = window_start + step

            points =
              Enum.filter(all_points, fn {ts, _v} ->
                ts >= window_start and ts < window_end
              end)

            case compute(fun, points) do
              :omit -> []
              {:ok, value} -> [{window_start, value}]
            end
          end)

        {entry.labels, range_points}
      end)
      |> Enum.reject(fn {_labels, range_points} -> range_points == [] end)

    {:reply, result, state}
  end