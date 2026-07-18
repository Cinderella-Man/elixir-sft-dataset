  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(raw) when byte_size(raw) > @mac_size do
    signed_size = byte_size(raw) - @mac_size
    {:ok, binary_part(raw, 0, signed_size), binary_part(raw, signed_size, @mac_size)}
  end

  defp split_mac(_raw), do: {:error, :malformed}