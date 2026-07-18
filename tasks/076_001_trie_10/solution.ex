  # Walk down the trie following `chars`, returning the subtree or nil.
  defp descend(node, []), do: node

  defp descend(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end