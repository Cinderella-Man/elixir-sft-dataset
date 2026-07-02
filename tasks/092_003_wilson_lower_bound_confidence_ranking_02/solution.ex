def score(item, opts \\ []) when is_map(item) and is_list(opts) do
  z = Keyword.get(opts, :z, @default_z)

  upvotes = Map.fetch!(item, :upvotes)
  downvotes = Map.fetch!(item, :downvotes)
  n = upvotes + downvotes

  if n == 0 do
    0.0
  else
    p = upvotes / n
    z2 = z * z

    denominator = 1 + z2 / n
    center = p + z2 / (2 * n)
    margin = z * :math.sqrt((p * (1 - p) + z2 / (4 * n)) / n)

    (center - margin) / denominator
  end
end