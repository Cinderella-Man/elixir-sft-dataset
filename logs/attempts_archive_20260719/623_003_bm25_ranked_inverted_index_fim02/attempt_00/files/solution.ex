  @spec tokenize(String.t(), MapSet.t()) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(&Regex.split(@token_regex, &1, trim: true))
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end