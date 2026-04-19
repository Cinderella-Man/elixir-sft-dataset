@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  cleaned =
    state.counters
    |> Enum.reduce(%{}, fn {ck, {count, window_end} = entry}, acc ->
      # Keep only counters whose window has not yet ended.
      if window_end > now do
        Map.put(acc, ck, entry)
      else
        _ = count
        acc
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %{state | counters: cleaned}}
end
