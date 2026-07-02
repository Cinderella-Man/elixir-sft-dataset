defp flush_key(state, key, entry) do
  batch = Enum.reverse(entry.buffer)
  state.on_flush.(key, batch)
  clear_timer(entry)
  %{state | keys: Map.delete(state.keys, key)}
end