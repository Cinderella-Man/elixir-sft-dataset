@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  # Keep global refill up-to-date on cleanup too.
  state = refill_global(state, now)

  cleaned =
    Enum.reduce(state.buckets, %{}, fn {name, bucket}, acc ->
      elapsed = now - bucket.last_update_at
      projected = min(bucket.capacity * 1.0, bucket.free + elapsed * bucket.refill_rate / 1000)

      # Bucket indistinguishable from a fresh one — safe to drop.
      if projected >= bucket.capacity do
        acc
      else
        Map.put(acc, name, %{bucket | free: projected, last_update_at: now})
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)
  {:noreply, %{state | buckets: cleaned}}
end
