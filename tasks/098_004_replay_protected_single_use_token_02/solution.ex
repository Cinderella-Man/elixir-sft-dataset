  # Runs the full check pipeline. Returns the nonce and raw payload bytes so the
  # caller can consume the nonce only on the fully successful path.
  @spec verify(State.t(), term()) :: {:ok, binary(), binary()} | {:error, error()}
  defp verify(%State{} = state, token) when is_binary(token) do
    with {:ok, raw} <- decode(token),
         {:ok, signed, candidate_mac} <- split_mac(raw),
         {:ok, nonce, expires_at, payload_bytes} <- parse(signed),
         :ok <- check_mac(state.secret, signed, candidate_mac),
         :ok <- check_replay(state.consumed, nonce),
         :ok <- check_expiry(state.clock.(), expires_at) do
      {:ok, nonce, payload_bytes}
    end
  end

  defp verify(%State{}, _token), do: {:error, :malformed}