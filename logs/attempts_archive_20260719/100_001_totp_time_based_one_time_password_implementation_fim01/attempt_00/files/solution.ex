defp base32_encode(data) when is_binary(data), do: encode_groups(data, <<>>)

# Consume 5 bytes (40 bits) at a time, emit 8 characters.
defp encode_groups(
       <<a::5, b::5, c::5, d::5, e::5, f::5, g::5, h::5, rest::binary>>,
       acc
     ) do
  chunk = <<enc(a), enc(b), enc(c), enc(d), enc(e), enc(f), enc(g), enc(h)>>
  encode_groups(rest, <<acc::binary, chunk::binary>>)
end

defp encode_groups(<<>>, acc), do: acc

# 1–4 byte remainder: right-pad with zero bits to a 5-bit boundary, then emit.
defp encode_groups(rest, acc) when is_binary(rest) do
  pad = rem(5 - rem(bit_size(rest), 5), 5)
  encode_tail(<<rest::bitstring, 0::size(pad)>>, acc)
end

defp encode_tail(<<>>, acc), do: acc

defp encode_tail(<<x::5, rest::bitstring>>, acc),
  do: encode_tail(rest, <<acc::binary, enc(x)>>)

defp enc(i) when i in 0..25, do: ?A + i
defp enc(i) when i in 26..31, do: ?2 + (i - 26)