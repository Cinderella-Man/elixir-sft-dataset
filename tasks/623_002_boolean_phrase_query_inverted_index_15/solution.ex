  defp candidate_ids(terms, state) do
    terms
    |> Enum.map(&Map.get(state.postings, &1, MapSet.new()))
    |> intersect_all()
  end