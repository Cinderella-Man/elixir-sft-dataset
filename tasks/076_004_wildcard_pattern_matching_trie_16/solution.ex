  defp collect(%{terminal: terminal, children: children}, acc) do
    base = if terminal, do: [acc], else: []

    Enum.reduce(children, base, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end