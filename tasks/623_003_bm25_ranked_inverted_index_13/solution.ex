  @spec build_document(map(), MapSet.t()) :: {map(), map()}
  defp build_document(fields, stop_words) do
    Enum.reduce(fields, {%{}, %{}}, fn {field, text}, {terms_acc, lengths_acc} ->
      tokens = tokenize(text, stop_words)

      {Map.put(terms_acc, field, count_tokens(tokens)),
       Map.put(lengths_acc, field, length(tokens))}
    end)
  end