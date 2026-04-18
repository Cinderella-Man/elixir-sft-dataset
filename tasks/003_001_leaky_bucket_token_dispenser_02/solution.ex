@impl true
def handle_call({:acquire, bucket_name, capacity, refill_rate, tokens}, _from, %State{} = state) do
  now = state.clock.()

  bucket =
    case Map.get(state.buckets, bucket_name) do
      nil ->
        # Brand-new bucket starts full at capacity.
        %Bucket{tokens: capacity * 1.0, last_access: now}

      existing ->
        refill(existing, now, capacity, refill_rate)
    end

  if bucket.tokens >= tokens do
    drained = %Bucket{bucket | tokens: bucket.tokens - tokens, last_access: now}
    new_state = %State{state | buckets: Map.put(state.buckets, bucket_name, drained)}
    {:reply, {:ok, floor(drained.tokens)}, new_state}
  else
    # How many tokens are we short?
    deficit = tokens - bucket.tokens
    # Time to refill the deficit at the given rate (tokens/sec → ms).
    retry_after_ms = ceil(deficit / refill_rate * 1000)

    # Still update last_access so the refilled tokens aren't lost and the
    # bucket isn't prematurely evicted by cleanup.
    touched = %Bucket{bucket | last_access: now}
    new_state = %State{state | buckets: Map.put(state.buckets, bucket_name, touched)}

    {:reply, {:error, :empty, retry_after_ms}, new_state}
  end
end
