@impl true
def handle_call({:check, key, max_requests, window_ms, ladder}, _from, state) do
  now = state.clock.()
  entry = Map.get(state.keys, key, empty_entry())

  # Step 1: decay strikes
  entry = decay_strikes(entry, now, window_ms)

  # ✅ FIX: expire cooldown if time has passed
  entry =
    if entry.cooldown_end && entry.cooldown_end <= now do
      %{entry | cooldown_end: nil}
    else
      entry
    end

  # Step 2: enforce cooldown if still active
  cond do
    entry.cooldown_end != nil and entry.cooldown_end > now ->
      retry_after = entry.cooldown_end - now

      {:reply, {:error, :cooling_down, retry_after, entry.strikes},
        %{state | keys: Map.put(state.keys, key, entry)}}

    true ->
      evaluate_window(state, key, entry, now, max_requests, window_ms, ladder)
  end
end
