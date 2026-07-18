  defp count_nodes(node) do
    Enum.reduce(node.edges, 1, fn {_key, %{child: child}}, acc -> acc + count_nodes(child) end)
  end