  @impl GenServer
  def handle_call({:push, side, record}, _from, state) do
    key = record_key(record, state.key_fields)

    case take_pending(state, opposite(side), key) do
      {:ok, counterpart, state} ->
        {left, right} = orient(side, record, counterpart)
        entry = build_entry(state, key, left, right)
        state = %{state | matches: state.matches ++ [entry]}
        {:reply, {:matched, entry}, state}

      :error ->
        {:reply, :pending, put_pending(state, side, key, record)}
    end
  end

  def handle_call(:take_matches, _from, state) do
    {:reply, state.matches, %{state | matches: []}}
  end

  def handle_call(:pending, _from, state) do
    reply = %{
      left: Map.values(state.pending_left),
      right: Map.values(state.pending_right)
    }

    {:reply, reply, state}
  end