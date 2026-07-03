  defp score(_p, []), do: 0

  defp score(p, query) do
    name_tokens = tokenize(p.name)
    desc_tokens = tokenize(Map.get(p, :description))

    Enum.reduce(query, 0, fn qt, acc ->
      acc + 3 * count_prefix(name_tokens, qt) + count_prefix(desc_tokens, qt)
    end)
  end