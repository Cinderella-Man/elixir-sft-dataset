  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(bytes) do
    pad = rem(5 - rem(bit_size(bytes), 5), 5)
    padded = <<bytes::bitstring, 0::size(pad)>>

    for <<chunk::5 <- padded>>, into: "" do
      binary_part(@alphabet, chunk, 1)
    end
  end