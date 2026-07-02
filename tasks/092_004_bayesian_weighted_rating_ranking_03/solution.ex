def rank(items, opts \\ []) when is_list(items) and is_list(opts) do
  opts =
    if Keyword.has_key?(opts, :mean) do
      opts
    else
      Keyword.put(opts, :mean, corpus_mean(items))
    end

  items
  |> Enum.map(fn item -> {score(item, opts), Map.fetch!(item, :vote_count), item} end)
  |> Enum.sort(fn {score_a, votes_a, _a}, {score_b, votes_b, _b} ->
    cond do
      score_a > score_b -> true
      score_a < score_b -> false
      votes_a > votes_b -> true
      votes_a < votes_b -> false
      true -> true
    end
  end)
  |> Enum.map(fn {_score, _votes, item} -> item end)
end