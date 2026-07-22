  def verify(token, secret, opts) when is_binary(token) and is_binary(secret) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _secret, _opts), do: {:error, :malformed}