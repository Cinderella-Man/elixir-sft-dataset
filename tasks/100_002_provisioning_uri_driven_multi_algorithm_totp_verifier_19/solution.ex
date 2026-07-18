  # Keeps every complete byte of `bits` and discards the trailing partial byte, if any.
  @spec whole_bytes(bitstring(), binary()) :: binary()
  defp whole_bytes(<<byte, rest::bitstring>>, acc), do: whole_bytes(rest, <<acc::binary, byte>>)
  defp whole_bytes(_leftover, acc), do: acc