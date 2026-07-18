  defp descend(node, []), do: node

  defp descend(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end