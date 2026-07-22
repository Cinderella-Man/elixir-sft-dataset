  defp do_dfs([], _visited, _out_edges, _target), do: false

  defp do_dfs([node | stack], visited, out_edges, target) do
    cond do
      node == target ->
        true

      MapSet.member?(visited, node) ->
        do_dfs(stack, visited, out_edges, target)

      true ->
        neighbors = out_edges |> Map.get(node, MapSet.new()) |> MapSet.to_list()
        do_dfs(neighbors ++ stack, MapSet.put(visited, node), out_edges, target)
    end
  end