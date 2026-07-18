  @spec decode_line(String.t()) :: {:ok, term()} | {:error, term()}
  defp decode_line(trimmed) do
    trimmed
    |> strip_trailing_comma()
    |> JSON.decode()
  end