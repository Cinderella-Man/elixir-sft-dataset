  @spec decode(binary()) :: {:ok, binary()} | :error
  defp decode(token), do: Base.url_decode64(token, padding: false)