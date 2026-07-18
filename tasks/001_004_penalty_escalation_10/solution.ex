  # A key is removed only when it has become indistinguishable from a
  # never-seen key: every timestamp has expired (judged against the window the
  # key was last checked with), the strike count has fully decayed, and no
  # cooldown is outstanding. Decay is computed here only to DECIDE removal —
  # retained entries keep their stored state, so decay still materializes
  # lazily at the next `check`.
  defp removable?(%{window_ms: nil}, _now), do: false

  defp removable?(entry, now) do
    decayed = decay_strikes(entry, now, entry.window_ms)
    window_start = now - entry.window_ms

    Enum.all?(decayed.timestamps, fn ts -> ts <= window_start end) and
      decayed.strikes == 0 and
      (decayed.cooldown_end == nil or decayed.cooldown_end <= now)
  end