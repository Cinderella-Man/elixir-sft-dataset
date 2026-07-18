  @impl true
  def handle_call({:record, key}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    state = %{state | keys: Map.put(state.keys, key, buckets)}
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:status, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:count, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, count_for(buckets, now, state), state}
  end