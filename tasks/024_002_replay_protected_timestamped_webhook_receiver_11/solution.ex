  @doc """
  Computes the lowercase hex HMAC-SHA256 of `"<timestamp>.<payload>"`.
  """
  @spec sign(integer() | binary(), binary(), binary()) :: String.t()
  def sign(timestamp, payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
    |> Base.encode16(case: :lower)
  end