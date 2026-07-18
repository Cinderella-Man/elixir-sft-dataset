  defp drop_posting(postings, term, id) do
    case Map.get(postings, term) do
      nil ->
        postings

      set ->
        set = MapSet.delete(set, id)

        if MapSet.size(set) == 0 do
          Map.delete(postings, term)
        else
          Map.put(postings, term, set)
        end
    end
  end