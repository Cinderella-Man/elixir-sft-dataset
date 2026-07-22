  defp cleanup_edge(node, key, edge, new_child) do
    cond do
      # dead-end leaf — prune it
      not new_child.terminal and map_size(new_child.edges) == 0 ->
        %{node | edges: Map.delete(node.edges, key)}

      # single non-terminal child — re-merge the labels
      not new_child.terminal and map_size(new_child.edges) == 1 ->
        [{_k, grand}] = Map.to_list(new_child.edges)
        merged = %{edge | label: edge.label <> grand.label, child: grand.child}
        %{node | edges: Map.put(node.edges, key, merged)}

      true ->
        %{node | edges: Map.put(node.edges, key, %{edge | child: new_child})}
    end
  end