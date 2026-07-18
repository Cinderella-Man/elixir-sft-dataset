  defp put_entry(state, key, entry) do
    %{state | keys: Map.put(state.keys, key, entry)}
  end