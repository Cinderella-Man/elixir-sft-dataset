  @impl true
  def handle_call({:process_payment, params, nil}, from, state) do
    if valid_params?(params) do
      ref = make_ref()
      start_work(state.processor, params, {:nil_req, ref})
      {:noreply, %{state | nil_pending: Map.put(state.nil_pending, ref, from)}}
    else
      {:reply, {:error, :invalid_params}, state}
    end
  end

  def handle_call({:process_payment, params, key}, from, state) do
    now = state.clock.()

    case Map.get(state.idempotency_keys, key) do
      {:completed, result, expiry} when expiry > now ->
        {:reply, result, state}

      {:pending, froms} ->
        keys = Map.put(state.idempotency_keys, key, {:pending, [from | froms]})
        {:noreply, %{state | idempotency_keys: keys}}

      _ ->
        if valid_params?(params) do
          start_work(state.processor, params, {:key, key})
          keys = Map.put(state.idempotency_keys, key, {:pending, [from]})
          {:noreply, %{state | idempotency_keys: keys}}
        else
          result = {:error, :invalid_params}
          expiry = now + state.ttl_ms
          keys = Map.put(state.idempotency_keys, key, {:completed, result, expiry})
          {:reply, result, %{state | idempotency_keys: keys}}
        end
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

  def handle_call(:in_flight_count, _from, state) do
    key_pending =
      Enum.count(state.idempotency_keys, fn {_k, v} -> match?({:pending, _}, v) end)

    {:reply, key_pending + map_size(state.nil_pending), state}
  end