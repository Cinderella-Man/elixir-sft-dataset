  @spec expired?(lease(), integer()) :: boolean()
  defp expired?(lease, now) do
    now >= lease.expires_at
  end