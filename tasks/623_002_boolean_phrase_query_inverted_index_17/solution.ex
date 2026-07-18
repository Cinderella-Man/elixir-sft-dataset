  defp contains_sequence?(tokens, terms) do
    len = length(terms)

    tokens
    |> Stream.chunk_every(len, 1, :discard)
    |> Enum.any?(&(&1 == terms))
  end