  defp contributions_for(q, vocab, index, max_distance) do
    matches =
      vocab
      |> Enum.map(fn t -> {t, edit_distance(q, t)} end)
      |> Enum.filter(fn {_t, d} -> d <= max_distance end)
      |> Enum.map(fn {t, d} -> {t, max_distance + 1 - d} end)

    Enum.reduce(matches, %{}, fn {t, similarity}, acc ->
      postings = Map.get(index, t, %{})

      Enum.reduce(postings, acc, fn {id, count}, inner ->
        value = similarity * count
        Map.update(inner, id, value, fn existing -> max(existing, value) end)
      end)
    end)
  end