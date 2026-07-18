  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    slice_index = div(now, state.slice_ms)
    slice_start = slice_index * state.slice_ms
    slot = rem(slice_index, state.slots)

    series = Map.get(state.series, name, %{})

    counts =
      case Map.get(series, slot) do
        {^slice_start, c} -> c
        _ -> %{}
      end

    bucket = bucket_index(value, state.edges_t, state.bucket_count)
    counts = Map.update(counts, bucket, 1, &(&1 + 1))
    series = Map.put(series, slot, {slice_start, counts})

    {:reply, :ok, %{state | series: Map.put(state.series, name, series)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    now = state.clock.()

    merged =
      state.series
      |> Map.get(name, %{})
      |> Map.values()
      |> Enum.filter(fn {slice_start, _} -> now - slice_start < state.window_ms end)
      |> Enum.reduce(%{}, fn {_s, c}, acc -> merge_counts(acc, c) end)

    result = quantile(merged, state.edges_t, state.bucket_count, percentile)
    {:reply, result, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end