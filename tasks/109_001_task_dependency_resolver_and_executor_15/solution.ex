  defp trim_feeders(stuck, dependents) do
    feeders =
      Enum.filter(stuck, fn id ->
        dependents |> Map.get(id, []) |> Enum.all?(&(not MapSet.member?(stuck, &1)))
      end)

    case feeders do
      [] -> stuck |> MapSet.to_list() |> Enum.sort()
      _ -> trim_feeders(MapSet.difference(stuck, MapSet.new(feeders)), dependents)
    end
  end