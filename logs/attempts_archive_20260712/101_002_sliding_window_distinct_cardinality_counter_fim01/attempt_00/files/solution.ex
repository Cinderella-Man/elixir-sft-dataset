  @impl true
  def handle_call({:add, key, member}, _from, state) do
    now = state.clock.()
    index = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    set = Map.get(buckets, index, MapSet.new())
    buckets = Map.put(buckets, index, MapSet.put(set, member))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:distinct_count, key, window_ms}, _from, state) do
    now = state.clock.()
    threshold = now - window_ms
    buckets = Map.get(state.keys, key, %{})

    union =
      Enum.reduce(buckets, MapSet.new(), fn {index, set}, acc ->
        if index * state.bucket_ms >= threshold do
          MapSet.union(acc, set)
        else
          acc
        end
      end)

    {:reply, MapSet.size(union), state}
  end

  def handle_call(:tracked_key_count, _from, state) do
    {:reply, map_size(state.keys), state}
  end