  @spec evict_expired([usage_entry()], integer(), non_neg_integer()) :: [usage_entry()]
  defp evict_expired(entries, now, window_ms) do
    cutoff = now - window_ms

    Enum.filter(entries, fn entry ->
      entry.recorded_at > cutoff
    end)
  end