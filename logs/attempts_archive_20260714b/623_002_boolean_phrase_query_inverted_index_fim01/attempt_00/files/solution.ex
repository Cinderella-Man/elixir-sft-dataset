  defp eval({:term, word}, state) do
    case tokenize(word, state.stop_words) do
      [] -> MapSet.new()
      [term | _rest] -> Map.get(state.postings, term, MapSet.new())
    end
  end

  defp eval({:phrase, text}, state) do
    case tokenize(text, state.stop_words) do
      [] ->
        MapSet.new()

      [single] ->
        Map.get(state.postings, single, MapSet.new())

      terms ->
        terms
        |> candidate_ids(state)
        |> Enum.filter(fn id -> doc_has_phrase?(Map.get(state.documents, id), terms) end)
        |> MapSet.new()
    end
  end

  defp eval({:and, []}, state), do: all_ids(state)

  defp eval({:and, list}, state) do
    list
    |> Enum.map(&eval(&1, state))
    |> intersect_all()
  end

  defp eval({:or, list}, state) do
    Enum.reduce(list, MapSet.new(), fn q, acc -> MapSet.union(acc, eval(q, state)) end)
  end

  defp eval({:not, expr}, state) do
    MapSet.difference(all_ids(state), eval(expr, state))
  end