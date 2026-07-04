  @spec verify(term(), term(), term(), term()) :: :ok | :error
  def verify(payload, signature, secret, prefix \\ "")

  def verify(payload, signature, secret, prefix)
      when is_binary(payload) and is_binary(signature) and
             is_binary(secret) and is_binary(prefix) do
    expected = prefix <> lower_hex_hmac(secret, payload)

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      :error
    end
  end

  def verify(_payload, _signature, _secret, _prefix), do: :error