  @spec average_length(map(), non_neg_integer(), map()) :: float()
  defp average_length(_docs, 0, _boosts), do: +0.0

  defp average_length(docs, n, boosts) do
    total =
      Enum.reduce(docs, +0.0, fn {_id, doc}, acc ->
        acc + weighted_length(doc, boosts)
      end)

    total / n
  end