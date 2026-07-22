  def seal(payload, key, ttl_seconds, opts \\ [])
      when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    now = now(opts)
    issued_at = now
    expires_at = now + ttl_seconds

    nonce = :crypto.strong_rand_bytes(@nonce_size)
    plaintext = :erlang.term_to_binary(payload)
    aad = <<issued_at::64, expires_at::64>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(@cipher, key, nonce, plaintext, aad, true)

    binary =
      <<nonce::binary-size(@nonce_size), issued_at::64, expires_at::64,
        tag::binary-size(@tag_size), ciphertext::binary>>

    Base.url_encode64(binary, padding: false)
  end