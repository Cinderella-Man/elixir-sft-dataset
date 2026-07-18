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
  def handle_call({:apply, cs, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(cs, order_total, now, state) do
      {:ok, code} ->
        raw = raw_discount(code, order_total)
        {actual, state2} = draw(state, cs, code, raw)
        state3 = record_use(state2, cs, user_id)
        {:reply, {:ok, actual}, state3}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remaining_budget, cs}, _from, state) do
    reply =
      case Map.fetch(state.codes, cs) do
        :error -> {:error, :not_found}
        {:ok, %{budget: nil}} -> {:ok, :unlimited}
        {:ok, %{budget: b}} -> {:ok, b - dispensed_of(state, cs)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:dispensed, cs}, _from, state) do
    reply =
      case Map.has_key?(state.codes, cs) do
        false -> {:error, :not_found}
        true -> {:ok, dispensed_of(state, cs)}
      end

    {:reply, reply, state}
  end