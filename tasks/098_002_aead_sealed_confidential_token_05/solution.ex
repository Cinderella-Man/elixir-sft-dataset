  def open(token, key, opts \\ []) do
    with true <- is_binary(token),
         {:ok, binary} <- decode(token),
         {:ok, nonce, issued_at, expires_at, tag, ciphertext} <- parse(binary) do
      decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts)
    else
      _ -> {:error, :malformed}
    end
  end