  defp validate_batch(:half), do: :half
  defp validate_batch(n) when is_integer(n) and n > 0, do: n