  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()
    cutoff = now - state.retention_ms

    new_series =
      state.series
      |> Enum.reduce(%{}, fn {key, entry}, acc ->
        kept = drop_expired_buckets(entry.buckets, cutoff, state.bucket_duration_ms)

        if map_size(kept) == 0 do
          acc
        else
          Map.put(acc, key, %{entry | buckets: kept})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | series: new_series}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end