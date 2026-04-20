# Single entry point for all bucket state transitions.  Applies elapsed-time
# refill math AND expires any lease whose deadline has passed (expired leases
# are treated as :completed — NO token refund).
defp refill_and_expire(bucket, now) do
  elapsed = now - bucket.last_update_at
  added = elapsed * bucket.refill_rate / 1000
  new_free = min(bucket.capacity * 1.0, bucket.free + added)

  # Expire leases where expires_at <= now.  Tokens are NOT refunded.
  active_leases =
    bucket.leases
    |> Enum.reject(fn {_id, {_tokens, expires_at}} -> expires_at <= now end)
    |> Enum.into(%{})

  %{bucket | free: new_free, last_update_at: now, leases: active_leases}
end
