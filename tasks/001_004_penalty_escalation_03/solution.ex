defp evaluate_window(state, key, entry, now, max_requests, window_ms, ladder) do
  window_start = now - window_ms

  # Timestamps are stored newest-first, so the scan stops at the first
  # expired entry.
  active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
  count = length(active)

  if count < max_requests do
    new_entry = %{entry | timestamps: [now | active], cooldown_end: nil, window_ms: window_ms}
    remaining = max_requests - count - 1

    {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
  else
    new_strikes = entry.strikes + 1
    cooldown_ms = ladder_value(ladder, new_strikes)

    # Newest-first order makes the last active entry the oldest one.
    oldest = List.last(active)
    window_retry = oldest + window_ms - now

    # retry_after covers both the window expiry and the new strike's cooldown.
    retry_after = max(max(window_retry, cooldown_ms), 1)

    new_entry = %{
      entry
      | # A rejected request does not consume a window slot.
        timestamps: active,
        strikes: new_strikes,
        last_strike_at: now,
        # The cooldown ends exactly retry_after past the moment the strike
        # was issued.
        cooldown_end: now + retry_after,
        window_ms: window_ms
    }

    {:reply, {:error, :rate_limited, retry_after, new_strikes},
     %{state | keys: Map.put(state.keys, key, new_entry)}}
  end
end
