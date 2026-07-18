  @spec do_search(map(), [String.t()], map()) :: [%{id: String.t(), score: float()}]
  defp do_search(_state, [], _boosts), do: []

  defp do_search(state, query_terms, boosts) do
    n = map_size(state.docs)
    avgdl = average_length(state.docs, n, boosts)

    query_terms
    |> candidates(state.postings)
    |> Enum.map(fn id ->
      doc = Map.fetch!(state.docs, id)

      score =
        score_doc(doc, query_terms, state.postings, n, avgdl, state.k1, state.b, boosts)

      %{id: id, score: score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end