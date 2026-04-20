@impl true
def handle_call({:acquire, name, key_cap, key_rate, tokens}, _from, state) do
  now = state.clock.()

  # Apply lazy refill to both levels BEFORE evaluating the drain.
  state = refill_global(state, now)
  {bucket, state} = get_and_refill_bucket(state, name, key_cap, key_rate, now)

  cond do
    bucket.free < tokens ->
      # Per-key is the blocker — signal :key_empty even if global is also short.
      deficit = tokens - bucket.free
      retry_after = ceil_positive(deficit * 1000 / key_rate)

      # Persist the refilled bucket state (no drain) so the refill clock
      # is up to date next time.
      new_buckets = Map.put(state.buckets, name, bucket)
      {:reply, {:error, :key_empty, retry_after}, %{state | buckets: new_buckets}}

    state.global_free < tokens ->
      # Per-key would have permitted, global is the blocker.
      deficit = tokens - state.global_free
      retry_after = ceil_positive(deficit * 1000 / state.global_refill_rate)

      new_buckets = Map.put(state.buckets, name, bucket)
      {:reply, {:error, :global_empty, retry_after}, %{state | buckets: new_buckets}}

    true ->
      # Drain both levels atomically.
      new_bucket = %{bucket | free: bucket.free - tokens}
      new_buckets = Map.put(state.buckets, name, new_bucket)
      new_global = state.global_free - tokens

      {:reply, {:ok, trunc(new_bucket.free), trunc(new_global)},
        %{state | buckets: new_buckets, global_free: new_global}}
  end
end
