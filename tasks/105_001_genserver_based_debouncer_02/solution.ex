@impl true
def handle_cast({:debounce, key, delay_ms, func}, state) do
  # Cancel any pending timer for this key so the burst is coalesced.
  case Map.get(state, key) do
    {timer_ref, _old_func} -> Process.cancel_timer(timer_ref)
    nil -> :ok
  end

  timer_ref = Process.send_after(self(), {:fire, key}, delay_ms)
  {:noreply, Map.put(state, key, {timer_ref, func})}
end