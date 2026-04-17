@impl true
def handle_call({:check, key, max_requests, window_ms}, _from, state) do
  now = state.clock.()

  # Fetch existing timestamps for this key (or empty list).
  {timestamps, _old_window} = Map.get(state.keys, key, {[], window_ms})

  # Prune timestamps that have fallen outside the sliding window.
  window_start = now - window_ms
  active = Enum.filter(timestamps, fn ts -> ts > window_start end)

  count = length(active)

  if count < max_requests do
    # Allow the request – record its timestamp.
    updated = [now | active]
    remaining = max_requests - count - 1

    new_keys = Map.put(state.keys, key, {updated, window_ms})
    {:reply, {:ok, remaining}, %{state | keys: new_keys}}
  else
    # Denied – compute how long until the oldest active entry expires.
    oldest = List.last(active)
    retry_after = oldest + window_ms - now
    retry_after = max(retry_after, 1)

    # Update state with the pruned list even on failure
    new_state = put_in(state.keys[key], {active, window_ms})

    {:reply, {:error, :rate_limited, retry_after}, new_state}
  end
end
