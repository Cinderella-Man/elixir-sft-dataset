  @impl true
  def handle_call({:put, key, value}, _from, state) do
    now = state.clock.()
    entry = %{value: value, access_ts: now}

    entries =
      cond do
        # Key already present — overwrite, no eviction, size unchanged.
        Map.has_key?(state.entries, key) ->
          Map.put(state.entries, key, entry)

        # New key, cache at capacity — evict LRU first.
        map_size(state.entries) >= state.capacity ->
          state.entries
          |> evict_lru()
          |> Map.put(key, entry)

        # New key, capacity available.
        true ->
          Map.put(state.entries, key, entry)
      end

    {:reply, :ok, %{state | entries: entries}}
  end

  def handle_call({:get, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, %{value: value} = entry} ->
        # Refresh access timestamp — LRU correctness requires this mutation.
        updated = %{entry | access_ts: state.clock.()}
        {:reply, {:ok, value}, %{state | entries: Map.put(state.entries, key, updated)}}

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, %{state | entries: Map.delete(state.entries, key)}}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.entries
      |> Enum.sort_by(fn {_k, %{access_ts: ts}} -> ts end, :desc)
      |> Enum.map(fn {k, _} -> k end)

    {:reply, keys, state}
  end