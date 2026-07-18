  @spec candidates([String.t()], map()) :: MapSet.t()
  defp candidates(query_terms, postings) do
    Enum.reduce(query_terms, MapSet.new(), fn t, acc ->
      case Map.get(postings, t) do
        nil -> acc
        ids -> MapSet.union(acc, ids)
      end
    end)
  end