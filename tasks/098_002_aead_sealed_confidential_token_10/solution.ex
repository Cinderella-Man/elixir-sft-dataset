  @spec parse(binary()) ::
          {:ok, binary(), non_neg_integer(), non_neg_integer(), binary(), binary()}
          | :error
  defp parse(
         <<nonce::binary-size(@nonce_size), issued_at::64, expires_at::64,
           tag::binary-size(@tag_size), ciphertext::binary>>
       ) do
    {:ok, nonce, issued_at, expires_at, tag, ciphertext}
  end

  defp parse(_binary), do: :error