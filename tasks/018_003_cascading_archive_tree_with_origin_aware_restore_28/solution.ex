  defp children_of(state, parent_id) do
    state.nodes
    |> Map.values()
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.sort_by(& &1.id)
  end