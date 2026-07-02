def score(item, opts \\ []) when is_map(item) and is_list(opts) do
  m = Keyword.get(opts, :min_votes, @default_min_votes)
  c = Keyword.get(opts, :mean, 0.0)

  r = Map.fetch!(item, :rating)
  v = Map.fetch!(item, :vote_count)

  denom = v + m

  if denom == 0 do
    1.0 * c
  else
    v / denom * r + m / denom * c
  end
end