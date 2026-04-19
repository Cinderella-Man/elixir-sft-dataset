@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  cleaned =
    Enum.reduce(state.keys, %{}, fn {key, {timestamps, widest}}, acc ->
      cutoff = now - widest
      active = Enum.take_while(timestamps, fn ts -> ts > cutoff end)

      if active == [] do
        acc
      else
        Map.put(acc, key, {active, widest})
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %{state | keys: cleaned}}
end
