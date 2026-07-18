  defp doc_terms(tokenized) do
    tokenized
    |> Enum.flat_map(fn {_field, tokens} -> tokens end)
    |> MapSet.new()
  end