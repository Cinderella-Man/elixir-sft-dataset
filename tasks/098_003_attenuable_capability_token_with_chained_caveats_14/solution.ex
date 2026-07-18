  @doc """
  Mints a fresh token for `identifier`, signed with `root_key` and carrying no
  caveats.

  Returns the URL-safe token binary.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> CapabilityToken.inspect_token(token)
      {:ok, %{identifier: "user:42", caveats: []}}
  """
  @spec mint(binary(), binary()) :: token()
  def mint(root_key, identifier) when is_binary(root_key) and is_binary(identifier) do
    signature = :crypto.mac(:hmac, :sha256, root_key, identifier)
    encode(identifier, [], signature)
  end