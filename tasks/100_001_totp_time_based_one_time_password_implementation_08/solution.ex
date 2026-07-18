  defp base32_decode!(str) when is_binary(str) do
    bits = decode_bits(String.upcase(str), <<>>)
    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(^byte_count), _::bitstring>> = bits
    bytes
  end