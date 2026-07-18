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
  def handle_call({:preview, cs, order_total}, _from, state) do
    reply =
      case Map.fetch(state.codes, cs) do
        :error ->
          {:error, :not_found}

        {:ok, code} ->
          case select_tier(code.tiers, order_total) do
            :below_min_order -> {:error, :below_min_order}
            {tier, index} -> {:ok, tier_discount(tier, order_total), index}
          end
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:apply, cs, order_total, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    now = state.clock.()

    case check(cs, order_total, user_id, now, state) do
      {:ok, _code, discount} ->
        {:reply, {:ok, discount}, record_use(state, cs, user_id)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end