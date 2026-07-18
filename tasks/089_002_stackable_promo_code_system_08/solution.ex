  @impl true
  def handle_call({:create, attrs}, _from, state) do
    with {:ok, code} <- build_code(attrs),
         :ok <- ensure_unique(code.code, state) do
      {:reply, {:ok, code}, put_in(state.codes[code.code], code)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply, [], _order_total, _opts}, _from, state) do
    {:reply, {:error, :no_codes}, state}
  end

  def handle_call({:apply, codes, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()
    {result, new_state} = process(codes, order_total, user_id, now, state)
    {:reply, {:ok, result}, new_state}
  end