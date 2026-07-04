  defp collect(node, prefix) do
    base = if node.weight > 0, do: [{prefix, node.weight}], else: []

    Enum.reduce(node.children, base, fn {char, child}, acc ->
      collect(child, prefix <> char) ++ acc
    end)
  end