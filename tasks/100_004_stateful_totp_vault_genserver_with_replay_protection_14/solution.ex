  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) do
    for <<index::5 <- binary>>, into: "", do: binary_part(@alphabet, index, 1)
  end