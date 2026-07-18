  @doc false
  def tokenize(text, stop_words, stem?) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> then(fn tokens ->
      if stem?, do: Enum.map(tokens, &stem/1), else: tokens
    end)
  end