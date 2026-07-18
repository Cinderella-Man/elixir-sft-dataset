  @spec chain(binary(), binary(), [caveat()]) :: binary()
  defp chain(root_key, identifier, caveats) do
    Enum.reduce(caveats, :crypto.mac(:hmac, :sha256, root_key, identifier), fn caveat, sig ->
      :crypto.mac(:hmac, :sha256, sig, caveat)
    end)
  end