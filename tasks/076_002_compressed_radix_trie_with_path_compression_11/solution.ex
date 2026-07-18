  defp collect(node, path) do
    base = if node.terminal, do: [path], else: []

    Enum.reduce(node.edges, base, fn {_key, %{label: label, child: child}}, acc ->
      collect(child, path <> label) ++ acc
    end)
  end