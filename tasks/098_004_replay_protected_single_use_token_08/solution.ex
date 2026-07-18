  @spec decode(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end