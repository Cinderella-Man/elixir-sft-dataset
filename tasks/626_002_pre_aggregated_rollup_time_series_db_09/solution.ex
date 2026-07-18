  @impl true
  def handle_cast({:insert, metric_name, labels, timestamp, value}, state) do
    key = series_key(metric_name, labels)
    bucket_start = div(timestamp, state.bucket_duration_ms) * state.bucket_duration_ms

    entry = Map.get(state.series, key, %{labels: labels, buckets: %{}})
    acc = Map.get(entry.buckets, bucket_start)
    new_acc = fold(acc, timestamp, value)

    new_buckets = Map.put(entry.buckets, bucket_start, new_acc)
    new_entry = %{entry | buckets: new_buckets}
    {:noreply, %{state | series: Map.put(state.series, key, new_entry)}}
  end