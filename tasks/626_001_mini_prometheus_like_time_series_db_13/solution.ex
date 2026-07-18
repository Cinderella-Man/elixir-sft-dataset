  defp labels_match?(_labels, matchers) when map_size(matchers) == 0, do: true

  defp labels_match?(labels, matchers) do
    Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end