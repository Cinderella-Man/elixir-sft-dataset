defp decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts) do
  aad = <<issued_at::64, expires_at::64>>

  case :crypto.crypto_one_time_aead(@cipher, key, nonce, ciphertext, aad, tag, false) do
    :error ->
      {:error, :invalid}

    plaintext when is_binary(plaintext) ->
      validate_and_deserialize(plaintext, expires_at, opts)
  end
end