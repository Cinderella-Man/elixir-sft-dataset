  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) do
    bits = for <<char <- string>>, into: <<>>, do: <<decode_char(char)::5>>
    for <<byte::8 <- bits>>, into: <<>>, do: <<byte>>
  end