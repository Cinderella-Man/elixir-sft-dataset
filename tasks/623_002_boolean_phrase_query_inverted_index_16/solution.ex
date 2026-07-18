  defp doc_has_phrase?(nil, _terms), do: false

  defp doc_has_phrase?(tokenized, terms) do
    Enum.any?(tokenized, fn {_field, tokens} -> contains_sequence?(tokens, terms) end)
  end