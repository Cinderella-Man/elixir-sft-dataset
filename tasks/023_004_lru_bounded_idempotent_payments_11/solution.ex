  @impl true
  def handle_call({:process_payment, params, nil}, _from, state) do
    {result, state} = do_process(state, params)
    {:reply, result, state}
  end

  def handle_call({:process_payment, params, key}, _from, state) do
    case Map.get(state.idempotency_keys, key) do
      {result, _tick} ->
        # Cache hit: return cached result and refresh recency.
        {tick, state} = next_tick(state)
        keys = Map.put(state.idempotency_keys, key, {result, tick})
        {:reply, result, %{state | idempotency_keys: keys}}

      nil ->
        {result, state} = do_process(state, params)
        state = insert_key(state, key, result)
        {:reply, result, state}
    end
  end

  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  def handle_call({:get_payment, id}, _from, state) do
    case Enum.find(state.payments, &(&1.id == id)) do
      nil -> {:reply, {:error, :not_found}, state}
      payment -> {:reply, {:ok, payment}, state}
    end
  end

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.idempotency_keys
      |> Enum.sort_by(fn {_key, {_result, tick}} -> tick end)
      |> Enum.map(fn {key, _} -> key end)

    {:reply, keys, state}
  end