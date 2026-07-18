  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {name, bucket}, acc ->
        bucket = refill_and_expire(bucket, now)

        # A bucket with no leases and full free balance is indistinguishable
        # from a never-seen one — safe to drop.
        if map_size(bucket.leases) == 0 and bucket.free >= bucket.capacity do
          acc
        else
          Map.put(acc, name, bucket)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}