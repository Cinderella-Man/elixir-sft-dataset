  @spec decode_char(byte()) :: non_neg_integer()
  defp decode_char(char) when char in ?A..?Z, do: char - ?A
  defp decode_char(char) when char in ?2..?7, do: char - ?2 + 26