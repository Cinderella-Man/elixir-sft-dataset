  @spec merge_states(tp_state(), tp_state()) :: tp_state()
  defp merge_states(%{added: la, removed: lr}, %{added: ra, removed: rr}) do
    %{
      added: MapSet.union(la, ra),
      removed: MapSet.union(lr, rr)
    }
  end