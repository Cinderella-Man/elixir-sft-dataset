  @spec check_replay(MapSet.t(binary()), binary()) :: :ok | {:error, :replayed}
  defp check_replay(consumed, nonce) do
    if MapSet.member?(consumed, nonce), do: {:error, :replayed}, else: :ok
  end