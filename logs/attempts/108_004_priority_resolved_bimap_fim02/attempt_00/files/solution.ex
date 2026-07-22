defp evict(state, key, value) do
  %{
    state
    | forward: Map.delete(state.forward, key),
      reverse: Map.delete(state.reverse, value),
      prio: Map.delete(state.prio, key)
  }
end