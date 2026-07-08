@impl true
def handle_cast({:debounce, key, delay_ms, func}, state) do
  # Cancel any pending timer for this key so the burst is coalesced. If the
  # old timer already fired, its message may be sitting in our queue —
  # cancellation cannot recall it, which is why every arm carries a unique
  # ref: handle_info/2 recognizes and drops the stale message.
  case Map.get(state, key) do
    {_ref, timer, _old_func} -> Process.cancel_timer(timer)
    nil -> :ok
  end

  ref = make_ref()
  timer = Process.send_after(self(), {:fire, key, ref}, delay_ms)
  {:noreply, Map.put(state, key, {ref, timer, func})}
end