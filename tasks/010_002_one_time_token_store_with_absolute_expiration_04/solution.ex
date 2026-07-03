  @spec expired?(token(), integer()) :: boolean()
  defp expired?(token, now) do
    now >= token.expires_at
  end