def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
  case Map.get(state, key) do
    nil ->
      # First call of a new burst: leading edges fire immediately.
      if edge in [:leading, :both], do: run(func)
      entry = Map.merge(arm(key, delay_ms), %{edge: edge, calls: 1, last_func: func})
      {:noreply, Map.put(state, key, entry)}

    %{timer: ref} = entry ->
      # cancel_timer/1 can return false with the old {:fire, …} already
      # sitting in the mailbox — the fresh token below makes that stale
      # message a no-op instead of an early trailing fire.
      Process.cancel_timer(ref)
      entry = %{entry | calls: entry.calls + 1, last_func: func}
      entry = Map.merge(entry, arm(key, delay_ms))
      {:noreply, Map.put(state, key, entry)}
  end
end