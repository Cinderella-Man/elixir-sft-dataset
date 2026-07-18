  test "authentic token whose plaintext is not a valid term returns :malformed" do
    now = Clock.now()
    nonce = :crypto.strong_rand_bytes(12)
    aad = <<now::64, now + 300::64>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, @key, nonce, "this-is-not-etf-data", aad, true)

    token =
      Base.url_encode64(
        <<nonce::binary-size(12), now::64, now + 300::64, tag::binary-size(16),
          ciphertext::binary>>,
        padding: false
      )

    assert {:error, :malformed} = open(token, @key)
  end