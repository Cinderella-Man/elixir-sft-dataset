  @spec remove_postings(map(), String.t(), map()) :: map()
  defp remove_postings(postings, id, terms) do
    Enum.reduce(doc_terms(terms), postings, fn t, acc ->
      case Map.get(acc, t) do
        nil ->
          acc

        ids ->
          ids = MapSet.delete(ids, id)
          if MapSet.size(ids) == 0, do: Map.delete(acc, t), else: Map.put(acc, t, ids)
      end
    end)
  end