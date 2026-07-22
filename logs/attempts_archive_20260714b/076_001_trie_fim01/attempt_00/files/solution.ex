  defp do_delete(node, []) do
    %{node | end_of_word: false}
  end

  defp do_delete(node, [char | rest]) do
    child = Map.fetch!(node.children, char)
    updated_child = do_delete(child, rest)

    if not updated_child.end_of_word and map_size(updated_child.children) == 0 do
      # The child is now a dead-end leaf — prune it.
      %{node | children: Map.delete(node.children, char)}
    else
      %{node | children: Map.put(node.children, char, updated_child)}
    end
  end