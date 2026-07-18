  @spec tokenize(String.t(), MapSet.t()) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> then(fn lowered -> Regex.split(~r/[^a-z0-9]+/, lowered, trim: true) end)
    |> Enum.reject(fn token -> MapSet.member?(stop_words, token) end)
  end