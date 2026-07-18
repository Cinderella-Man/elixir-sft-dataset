  defp prune_downstream(set, dependents) do
    next =
      set
      |> Enum.filter(fn id ->
        dependents
        |> Map.get(id, [])
        |> Enum.any?(&MapSet.member?(set, &1))
      end)
      |> MapSet.new()

    if MapSet.size(next) == MapSet.size(set) do
      Enum.to_list(next)
    else
      prune_downstream(next, dependents)
    end
  end