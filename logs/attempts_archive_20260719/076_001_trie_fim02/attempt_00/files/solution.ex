  # Depth-first collection of all complete words beneath `node`.
  defp collect(%{end_of_word: eow, children: children}, acc) do
    current = if eow, do: [acc], else: []

    children
    |> Enum.reduce(current, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end