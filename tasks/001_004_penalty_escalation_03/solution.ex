defp evaluate_window(state, key, entry, now, max_requests, window_ms, ladder) do
  window_start = now - window_ms

  # Highly efficient: stops traversing as soon as we hit expired timestamps
  active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
  count = length(active)

  if count < max_requests do
    # O(1) prepend
    new_entry = %{entry | timestamps: [now | active], cooldown_end: nil}
    remaining = max_requests - count - 1

    {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
  else
    new_strikes = entry.strikes + 1
    cooldown_ms = ladder_value(ladder, new_strikes)

    # List.last is perfectly safe because monotonic time + prepending guarantees order
    oldest = List.last(active)
    window_retry = oldest + window_ms - now

    # Calculate the true retry duration
    retry_after = max(max(window_retry, cooldown_ms), 1)

    new_entry = %{
      entry
      | timestamps: active,          # Do NOT add 'now' for rejected requests
        strikes: new_strikes,
        last_strike_at: now,
        cooldown_end: now + retry_after # Fixed: Align stored state with returned value
    }

    {:reply, {:error, :rate_limited, retry_after, new_strikes},
      %{state | keys: Map.put(state.keys, key, new_entry)}}
  end
end
