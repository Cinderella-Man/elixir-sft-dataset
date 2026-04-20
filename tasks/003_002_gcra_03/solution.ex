@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()
  idle_threshold = state.cleanup_idle_ms

  cleaned =
    Enum.reduce(state.buckets, %{}, fn {bucket, tat}, acc ->
      # If TAT is far enough in the past that the bucket would behave
      # identically to a fresh one, drop it.
      if now - tat >= idle_threshold do
        acc
      else
        Map.put(acc, bucket, tat)
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)
  {:noreply, %{state | buckets: cleaned}}
end
