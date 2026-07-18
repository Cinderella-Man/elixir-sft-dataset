  @impl true
  def handle_call({:query, metric_name, label_matchers, start_ts, end_ts}, _from, state) do
    result =
      state.series
      |> Enum.filter(fn {{name, _sorted}, entry} ->
        name == metric_name and matches?(entry.labels, label_matchers)
      end)
      |> Enum.map(fn {_key, entry} ->
        {entry.labels, buckets_in_range(entry.buckets, start_ts, end_ts)}
      end)
      |> Enum.reject(fn {_labels, buckets} -> buckets == [] end)

    {:reply, result, state}
  end