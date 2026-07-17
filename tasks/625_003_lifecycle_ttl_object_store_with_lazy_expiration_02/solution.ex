  @spec compute_expires_at(ttl(), integer()) :: number() | :infinity
  defp compute_expires_at(:infinity, _now), do: :infinity
  defp compute_expires_at(ttl_ms, now), do: now + ttl_ms