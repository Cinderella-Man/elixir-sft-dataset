  defp should_refresh?(entry, now, threshold) do
    age = now - (entry.expires_at - entry.ttl_ms)
    age >= threshold * entry.ttl_ms
  end