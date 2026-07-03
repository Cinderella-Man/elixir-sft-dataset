def verify(payload, signature, secret)
    when is_binary(payload) and is_binary(signature) and is_binary(secret) do
  expected =
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)

  if Plug.Crypto.secure_compare(expected, signature) do
    :ok
  else
    :error
  end
end

def verify(_payload, _signature, _secret), do: :error