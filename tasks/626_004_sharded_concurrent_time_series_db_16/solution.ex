  defp label_match?(sorted_labels, matchers) do
    lmap = Map.new(sorted_labels)
    Enum.all?(matchers, fn {k, v} -> Map.fetch(lmap, k) == {:ok, v} end)
  end