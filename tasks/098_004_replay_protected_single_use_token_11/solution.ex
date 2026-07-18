  @spec check_mac(binary(), binary(), binary()) :: :ok | {:error, :invalid_signature}
  defp check_mac(secret, signed, candidate_mac) do
    if constant_time_equal?(mac(secret, signed), candidate_mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end