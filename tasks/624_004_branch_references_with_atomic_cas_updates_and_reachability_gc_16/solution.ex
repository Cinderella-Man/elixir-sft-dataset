  @spec reachable_set(state) :: MapSet.t(hash)
  defp reachable_set(state) do
    heads = Map.values(state.branches)
    walk(heads, state.objects, MapSet.new())
  end