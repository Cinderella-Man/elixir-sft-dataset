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

      # Decay forgives cooldowns: once any strike decays, an outstanding
      # cooldown is cancelled and the next request is evaluated against the
      # normal sliding-window limit.
      %{
        entry
        | strikes: new_strikes,
          last_strike_at: new_last,
          cooldown_end: nil
      }
  end
end
