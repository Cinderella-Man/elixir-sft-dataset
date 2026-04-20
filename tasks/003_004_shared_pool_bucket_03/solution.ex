defp get_and_refill_bucket(state, name, key_cap, key_rate, now) do
  bucket =
    case Map.fetch(state.buckets, name) do
      {:ok, existing} ->
        # Allow capacity/rate to be updated mid-stream.
        %{existing | capacity: key_cap, refill_rate: key_rate}

      :error ->
        %{
          free: key_cap * 1.0,
          capacity: key_cap,
          refill_rate: key_rate,
          last_update_at: now
        }
    end

  elapsed = now - bucket.last_update_at
  added = elapsed * bucket.refill_rate / 1000
  new_free = min(bucket.capacity * 1.0, bucket.free + added)

  {%{bucket | free: new_free, last_update_at: now}, state}
end
