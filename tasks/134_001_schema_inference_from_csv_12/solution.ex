  @spec boolean?(String.t()) :: boolean()
  defp boolean?(value), do: String.downcase(value) in ["true", "false"]