  @spec token_counts([String.t()]) :: %{optional(String.t()) => pos_integer()}
  defp token_counts(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end