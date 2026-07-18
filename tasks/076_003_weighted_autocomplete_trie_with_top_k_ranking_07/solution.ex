  defp do_insert(node, [], weight) do
    delta = if node.weight == 0, do: 1, else: 0
    {%{node | weight: node.weight + weight}, delta}
  end

  defp do_insert(node, [char | rest], weight) do
    child = Map.get(node.children, char, new_node())
    {new_child, delta} = do_insert(child, rest, weight)
    {%{node | children: Map.put(node.children, char, new_child)}, delta}
  end