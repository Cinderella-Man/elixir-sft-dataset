  @spec expired?(map(), integer()) :: boolean()
  defp expired?(%{expires_at: :infinity}, _now), do: false
  defp expired?(%{expires_at: expires_at}, now), do: now >= expires_at