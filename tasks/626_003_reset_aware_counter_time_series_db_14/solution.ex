  @spec matches?(labels(), labels()) :: boolean()
  defp matches?(labels, matchers) do
    Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end