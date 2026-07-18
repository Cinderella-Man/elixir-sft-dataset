  @spec float?(String.t()) :: boolean()
  defp float?(value), do: Regex.match?(~r/^[+-]?\d+\.\d+$/, value)