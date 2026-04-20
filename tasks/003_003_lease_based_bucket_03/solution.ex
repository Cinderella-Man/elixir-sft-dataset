@impl true
def handle_call({:acquire_lease, bucket_name, capacity, refill_rate, tokens, timeout_ms}, _from, state) do
  now = state.clock.()

  bucket = get_bucket(state, bucket_name, capacity, refill_rate, now)
  bucket = refill_and_expire(bucket, now)

  if bucket.free >= tokens do
    lease_id = make_ref()
    lease = {tokens, now + timeout_ms}

    new_bucket = %{
      bucket
      | free: bucket.free - tokens,
        leases: Map.put(bucket.leases, lease_id, lease)
    }

    remaining = trunc(new_bucket.free)

    {:reply, {:ok, lease_id, remaining},
      %{state | buckets: Map.put(state.buckets, bucket_name, new_bucket)}}
  else
    # Not enough free tokens.  Compute how long until the deficit refills.
    deficit = tokens - bucket.free
    retry_after = ceil_positive(deficit * 1000 / refill_rate)

    # Persist the refill-expire update even on failure.
    {:reply, {:error, :empty, retry_after},
      %{state | buckets: Map.put(state.buckets, bucket_name, bucket)}}
  end
end
