  @spec count_tokens([String.t()]) :: %{optional(String.t()) => pos_integer()}
  defp count_tokens(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end