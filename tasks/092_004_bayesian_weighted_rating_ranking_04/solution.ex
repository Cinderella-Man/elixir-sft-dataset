defp corpus_mean([]), do: 0.0

defp corpus_mean(items) do
  ratings = Enum.map(items, &Map.fetch!(&1, :rating))
  Enum.sum(ratings) / length(ratings)
end