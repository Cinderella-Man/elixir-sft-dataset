def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
  now = mono_ms()

  first_at =
    case Map.get(state, key) do
      %{timer: ref, first_at: at} ->
        Process.cancel_timer(ref)
        at

      nil ->
        now
    end

  remaining_until_max = max(0, first_at + max_ms - now)
  fire_in = max(0, min(delay_ms, remaining_until_max))
  ref = Process.send_after(self(), {:fire, key}, fire_in)

  entry = %{timer: ref, func: func, first_at: first_at}
  {:noreply, Map.put(state, key, entry)}
end