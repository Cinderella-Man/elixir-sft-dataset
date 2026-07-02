def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
  case Map.get(state, key) do
    nil ->
      # First call of a new burst: leading edges fire immediately.
      if edge in [:leading, :both], do: run(func)
      ref = Process.send_after(self(), {:fire, key}, delay_ms)
      entry = %{timer: ref, edge: edge, calls: 1, last_func: func}
      {:noreply, Map.put(state, key, entry)}

    %{timer: ref} = entry ->
      Process.cancel_timer(ref)
      new_ref = Process.send_after(self(), {:fire, key}, delay_ms)
      entry = %{entry | timer: new_ref, calls: entry.calls + 1, last_func: func}
      {:noreply, Map.put(state, key, entry)}
  end
end