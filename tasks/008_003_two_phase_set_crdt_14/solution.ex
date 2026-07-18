  @spec compute_members(tp_state()) :: MapSet.t()
  defp compute_members(%{added: added, removed: removed}) do
    MapSet.difference(added, removed)
  end