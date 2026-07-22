defp do_delete(node, []), do: %{node | terminal: false}

defp do_delete(node, [char | rest]) do
  child = Map.fetch!(node.children, char)
  new_child = do_delete(child, rest)

  if not new_child.terminal and map_size(new_child.children) == 0 do
    %{node | children: Map.delete(node.children, char)}
  else
    %{node | children: Map.put(node.children, char, new_child)}
  end
end