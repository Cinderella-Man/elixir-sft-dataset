  @spec add_postings(map(), String.t(), map()) :: map()
  defp add_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      Map.update(acc, t, MapSet.new([id]), &MapSet.put(&1, id))
    end)
  end