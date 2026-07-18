  @spec encode_component(String.t()) :: String.t()
  defp encode_component(value), do: URI.encode(value, &URI.char_unreserved?/1)