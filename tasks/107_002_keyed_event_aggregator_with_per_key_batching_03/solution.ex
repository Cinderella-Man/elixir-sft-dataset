@impl true
def handle_cast({:push, key, event}, state) do
  entry = Map.get(state.keys, key, new_entry())

  # Buffers are stored in reverse push order for O(1) prepend and reversed
  # into push order right before being handed to the callback.
  entry = %{entry | buffer: [event | entry.buffer], count: entry.count + 1}
  entry = ensure_timer(entry, key, state.interval_ms)

  state =
    if entry.count >= state.batch_size do
      flush_key(state, key, entry)
    else
      put_entry(state, key, entry)
    end

  {:noreply, state}
end