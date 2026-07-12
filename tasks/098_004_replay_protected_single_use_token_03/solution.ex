  @spec build_token(State.t(), term(), pos_integer()) :: token()
  defp build_token(%State{secret: secret, clock: clock}, payload, ttl_seconds) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)
    issued_at = clock.()
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)

    signed =
      <<nonce::binary-size(@nonce_size), issued_at::signed-integer-64,
        expires_at::signed-integer-64, byte_size(payload_bytes)::unsigned-integer-32,
        payload_bytes::binary>>

    Base.url_encode64(signed <> mac(secret, signed), padding: false)
  end