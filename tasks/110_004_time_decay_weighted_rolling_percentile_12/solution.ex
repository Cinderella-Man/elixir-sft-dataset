  defp validate_optional_positive(nil), do: nil
  defp validate_optional_positive(n) when is_integer(n) and n > 0, do: n

  defp validate_optional_positive(other) do
    raise ArgumentError, ":max_samples must be a positive integer, got: #{inspect(other)}"
  end