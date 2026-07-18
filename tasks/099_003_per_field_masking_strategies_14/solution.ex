  @spec digit?(String.t()) :: boolean()
  defp digit?(<<c>>) when c >= ?0 and c <= ?9, do: true
  defp digit?(_ch), do: false