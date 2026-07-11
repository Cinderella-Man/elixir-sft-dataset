  @spec ancestors_walk([hash()], map(), MapSet.t()) :: MapSet.t()
  defp ancestors_walk([], _objects, visited), do: visited

  defp ancestors_walk([node | rest], objects, visited) do
    if MapSet.member?(visited, node) do
      ancestors_walk(rest, objects, visited)
    else
      visited = MapSet.put(visited, node)
      %{parents: parents} = parse_commit(Map.fetch!(objects, node))
      ancestors_walk(parents ++ rest, objects, visited)
    end
  end