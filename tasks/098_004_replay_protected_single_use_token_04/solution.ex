  @impl true
  def handle_call({:issue, payload, ttl_seconds}, _from, %State{} = state) do
    {:reply, build_token(state, payload, ttl_seconds), state}
  end

  def handle_call({:redeem, token}, _from, %State{} = state) do
    case verify(state, token) do
      {:ok, nonce, payload_bytes} ->
        consumed = MapSet.put(state.consumed, nonce)
        {:reply, {:ok, deserialize(payload_bytes)}, %State{state | consumed: consumed}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end