defp refill(%Bucket{} = bucket, now, capacity, refill_rate) do
  elapsed_ms = max(now - bucket.last_access, 0)
  new_tokens = min(capacity * 1.0, bucket.tokens + elapsed_ms * refill_rate / 1000)
  %Bucket{bucket | tokens: new_tokens}
end