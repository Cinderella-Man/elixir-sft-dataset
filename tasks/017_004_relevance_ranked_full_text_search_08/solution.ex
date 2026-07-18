  defp count_prefix(tokens, qt) do
    Enum.count(tokens, fn t -> String.starts_with?(t, qt) end)
  end