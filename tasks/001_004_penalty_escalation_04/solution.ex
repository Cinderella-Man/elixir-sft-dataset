defp decay_strikes(entry, now, window_ms) do
  decay_period = window_ms * 10
  elapsed = now - entry.last_strike_at
  forgive = div(elapsed, decay_period)

  cond do
    forgive <= 0 ->
      entry

    forgive >= entry.strikes ->
      empty_entry()

    true ->
      new_strikes = entry.strikes - forgive
      new_last = entry.last_strike_at + forgive * decay_period

      # ✅ Recalculate cooldown based on the NEW strike level
      # We approximate the "new cooldown" as if it started at new_last
      # using the ladder logic (same as when strike was created)
      # BUT since we don't have ladder here, safest option:

      %{
        entry
        | strikes: new_strikes,
          last_strike_at: new_last,
          cooldown_end: nil   # 🔑 clear stale cooldown
      }
  end
end
