  defp lower_hex_hmac(secret, payload) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end