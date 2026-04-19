@impl true
def handle_info(:cleanup, state) do
  now = state.clock.()

  cleaned =
    Enum.reduce(state.keys, %{}, fn {key, entry}, acc ->
      # NEW: drop expired timestamps
      active = Enum.take_while(entry.timestamps, fn ts -> ts > now end)
      entry = %{entry | timestamps: active}

      cooldown_active = entry.cooldown_end != nil and entry.cooldown_end > now
      has_strikes = entry.strikes > 0
      has_timestamps = active != []

      if cooldown_active or has_strikes or has_timestamps do
        Map.put(acc, key, entry)
      else
        acc
      end
    end)

  schedule_cleanup(state.cleanup_interval_ms)

  {:noreply, %{state | keys: cleaned}}
end
