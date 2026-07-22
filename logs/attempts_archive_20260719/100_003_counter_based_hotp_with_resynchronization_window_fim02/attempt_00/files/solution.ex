  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) do
    {bytes, _buffer, _bits} =
      string
      |> String.upcase()
      |> String.to_charlist()
      |> Enum.reduce({<<>>, 0, 0}, fn char, {acc, buffer, bits} ->
        buffer = buffer <<< 5 ||| Map.fetch!(@decode_map, char)
        bits = bits + 5

        if bits >= 8 do
          remaining = bits - 8
          byte = buffer >>> remaining &&& 0xFF
          {<<acc::binary, byte>>, buffer, remaining}
        else
          {acc, buffer, bits}
        end
      end)

    bytes
  end