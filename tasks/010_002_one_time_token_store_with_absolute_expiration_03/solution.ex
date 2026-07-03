  @impl GenServer
  def handle_call({:mint, payload, opts}, _from, state) do
    token_id = generate_token_id()
    now = state.clock.()
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)

    token = %{payload: payload, expires_at: now + ttl_ms}
    new_tokens = Map.put(state.tokens, token_id, token)

    {:reply, {:ok, token_id}, %{state | tokens: new_tokens}}
  end

  def handle_call({:verify, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        {:reply, {:ok, token.payload}, state}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:redeem, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:ok, token.payload}, %{state | tokens: new_tokens}}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:revoke, token_id}, _from, state) do
    new_tokens = Map.delete(state.tokens, token_id)
    {:reply, :ok, %{state | tokens: new_tokens}}
  end

  def handle_call(:active_count, _from, state) do
    now = state.clock.()

    count =
      Enum.count(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    {:reply, count, state}
  end