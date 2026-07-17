  @impl GenServer
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    if current_usage + amount > quota do
      overage = current_usage + amount - quota

      # Lazily clean up state using max_window_ms
      retained_entries = evict_expired(entries, now, state.max_window_ms)

      new_entries =
        if retained_entries == [] do
          Map.delete(state.entries, key)
        else
          Map.put(state.entries, key, retained_entries)
        end

      {:reply, {:error, :quota_exceeded, overage}, %{state | entries: new_entries}}
    else
      new_entry = %{amount: amount, recorded_at: now}

      # Retain up to max_window_ms, append the new entry
      retained_entries = evict_expired(entries, now, state.max_window_ms)
      updated = [new_entry | retained_entries]
      new_entries = Map.put(state.entries, key, updated)

      remaining = quota - (current_usage + amount)
      {:reply, {:ok, remaining}, %{state | entries: new_entries}}
    end
  end

  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    remaining = quota - current_usage
    {:reply, {:ok, remaining}, %{state | entries: new_entries}}
  end

  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    total = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    {:reply, {:ok, total}, %{state | entries: new_entries}}
  end

  def handle_call({:reset, key}, _from, state) do
    new_entries = Map.delete(state.entries, key)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.entries), state}
  end