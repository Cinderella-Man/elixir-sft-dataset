  defp evict_expired(t, now, ttl_ms) do
    cutoff = now - ttl_ms

    live =
      Enum.drop_while(t.history, fn {ts, _evt} -> ts < cutoff end)

    %{t | history: live}
  end