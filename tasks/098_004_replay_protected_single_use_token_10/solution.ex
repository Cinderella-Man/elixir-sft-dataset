  @spec parse(binary()) :: {:ok, binary(), integer(), binary()} | {:error, :malformed}
  defp parse(
         <<nonce::binary-size(@nonce_size), _issued_at::signed-integer-64,
           expires_at::signed-integer-64, payload_size::unsigned-integer-32,
           payload_bytes::binary>>
       )
       when byte_size(payload_bytes) == payload_size do
    {:ok, nonce, expires_at, payload_bytes}
  end

  defp parse(_signed), do: {:error, :malformed}