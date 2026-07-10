defp parse_data(
       <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32, rest::binary>>
     )
     when byte_size(rest) == payload_size do
  {:ok, issued_at, expires_at, rest}
end

defp parse_data(_), do: {:error, :malformed}