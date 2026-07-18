  defp do_insert(node, []), do: %{node | terminal: true}

  defp do_insert(node, [char | rest]) do
    child = Map.get(node.children, char, new_node())
    %{node | children: Map.put(node.children, char, do_insert(child, rest))}
  end