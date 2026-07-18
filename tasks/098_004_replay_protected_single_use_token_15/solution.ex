  @spec mac(binary(), binary()) :: binary()
  defp mac(secret, data), do: :crypto.mac(:hmac, :sha256, secret, data)