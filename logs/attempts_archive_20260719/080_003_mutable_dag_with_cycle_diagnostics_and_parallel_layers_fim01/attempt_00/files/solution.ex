  defp do_reach(out_edges, current, target, visited, acc) do
    cond do
      current == target ->
        Enum.reverse([current | acc])

      MapSet.member?(visited, current) ->
        nil

      true ->
        visited = MapSet.put(visited, current)

        out_edges
        |> Map.get(current, MapSet.new())
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.find_value(fn neighbor ->
          do_reach(out_edges, neighbor, target, visited, [current | acc])
        end)
    end
  end