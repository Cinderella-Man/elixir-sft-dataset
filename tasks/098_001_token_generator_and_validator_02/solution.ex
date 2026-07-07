  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32,
        payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)

    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end