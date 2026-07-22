  @spec dfs_post(hash(), map(), [hash()], MapSet.t()) :: {[hash()], MapSet.t()}
  defp dfs_post(node, objects, acc, visited) do
    if MapSet.member?(visited, node) do
      {acc, visited}
    else
      visited = MapSet.put(visited, node)
      %{parents: parents} = parse_commit(Map.fetch!(objects, node))

      {acc, visited} =
        Enum.reduce(parents, {acc, visited}, fn parent, {inner_acc, inner_visited} ->
          dfs_post(parent, objects, inner_acc, inner_visited)
        end)

      {[node | acc], visited}
    end
  end