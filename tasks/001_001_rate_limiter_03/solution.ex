@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  cleaned =
    state.keys
    |> Enum.reduce(%{}, fn {key, {timestamps, window_ms}}, acc ->
      window_start = now - window_ms
      active = Enum.filter(timestamps, fn ts -> ts > window_start end)

      # Drop the key entirely when no active timestamps remain.
      if active == [] do
        acc
      else
        Map.put(acc, key, {active, window_ms})
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %{state | keys: cleaned}}
end
