  defp decode(token) do
    with {:ok, binary} <- Base.url_decode64(token, padding: false),
         <<@version, id_size::16, identifier::binary-size(id_size), count::16, rest::binary>> <-
           binary,
         {:ok, caveats, <<signature::binary-size(@sig_size)>>} <- take_caveats(count, rest, []) do
      {:ok, identifier, caveats, signature}
    else
      _other -> {:error, :malformed}
    end
  end