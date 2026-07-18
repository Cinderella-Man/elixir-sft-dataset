  defp do_search(state, query, max_distance, limit) do
    terms = query |> tokenize(state.stop_words) |> Enum.uniq()

    cond do
      map_size(state.docs) == 0 ->
        []

      terms == [] ->
        []

      true ->
        vocab = Map.keys(state.index)

        scores =
          Enum.reduce(terms, %{}, fn q, acc ->
            contributions = contributions_for(q, vocab, state.index, max_distance)
            Map.merge(acc, contributions, fn _id, s1, s2 -> s1 + s2 end)
          end)

        scores
        |> Enum.filter(fn {_id, score} -> score > 0 end)
        |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
        |> Enum.sort_by(fn %{score: score} -> score end, :desc)
        |> apply_limit(limit)
    end
  end