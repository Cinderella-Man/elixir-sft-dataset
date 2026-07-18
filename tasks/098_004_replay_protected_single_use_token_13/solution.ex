  @spec check_expiry(integer(), integer()) :: :ok | {:error, :expired}
  defp check_expiry(now, expires_at) do
    if now < expires_at, do: :ok, else: {:error, :expired}
  end