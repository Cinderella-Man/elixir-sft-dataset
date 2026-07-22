  @doc """
  Decodes an unpadded, uppercase RFC 4648 base32 string into a binary.

  Leftover bits that do not complete a byte are discarded.
  """
  @spec base32_decode(String.t()) :: binary()
  def base32_decode(string) do
    string
    |> String.to_charlist()
    |> Enum.reduce(<<>>, fn char, acc ->
      <<acc::bitstring, base32_value(char)::size(5)>>
    end)
    |> whole_bytes(<<>>)
  end