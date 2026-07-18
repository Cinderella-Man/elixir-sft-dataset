  @spec integer?(String.t()) :: boolean()
  defp integer?(value), do: Regex.match?(~r/^[+-]?\d+$/, value)