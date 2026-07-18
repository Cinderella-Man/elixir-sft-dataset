  @impl true
  def handle_call({:create, attrs}, _from, state) do
    with {:ok, code} <- build_code(attrs),
         :ok <- ensure_unique(code.code, state) do
      new_state = put_in(state.codes[code.code], code)
      {:reply, {:ok, code}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply, code_string, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(code_string, order_total, user_id, now, state) do
      {:ok, _code, discount} ->
        new_state = record_use(state, code_string, user_id)
        {:reply, {:ok, discount}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end