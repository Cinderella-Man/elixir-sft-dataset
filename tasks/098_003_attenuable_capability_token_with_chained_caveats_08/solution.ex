  @spec encode(binary(), [caveat()], binary()) :: token()
  defp encode(identifier, caveats, signature) do
    body =
      for caveat <- caveats, into: <<>> do
        <<byte_size(caveat)::16, caveat::binary>>
      end

    binary =
      <<@version, byte_size(identifier)::16, identifier::binary, length(caveats)::16,
        body::binary, signature::binary-size(@sig_size)>>

    Base.url_encode64(binary, padding: false)
  end