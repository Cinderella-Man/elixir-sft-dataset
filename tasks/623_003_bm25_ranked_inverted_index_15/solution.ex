  @spec doc_terms(map()) :: MapSet.t()
  defp doc_terms(terms) do
    terms
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn tmap, acc ->
      MapSet.union(acc, MapSet.new(Map.keys(tmap)))
    end)
  end