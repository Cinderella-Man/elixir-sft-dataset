  defp put_key_state(state, key, key_state) do
    %{state | keys: Map.put(state.keys, key, key_state)}
  end