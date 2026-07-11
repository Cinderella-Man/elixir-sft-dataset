  defp touch(state, key) do
    %{state | access: Map.put(state.access, key, state.clock), clock: state.clock + 1}
  end