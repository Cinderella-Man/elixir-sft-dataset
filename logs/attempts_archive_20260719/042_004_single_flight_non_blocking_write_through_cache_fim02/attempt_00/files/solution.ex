  @impl GenServer
  def handle_call({:join, table, key}, from, state) do
    {tid, state} = ensure_table(table, state)

    case :ets.lookup(tid, key) do
      [{^key, value}] ->
        {:reply, {:hit, value}, state}

      [] ->
        flight_key = {table, key}

        case Map.get(state.inflight, flight_key) do
          nil ->
            leader = elem(from, 0)
            mref = Process.monitor(leader)
            entry = %{leader: leader, mref: mref, waiters: []}
            inflight = Map.put(state.inflight, flight_key, entry)
            {:reply, {:leader, mref}, %{state | inflight: inflight}}

          entry ->
            entry = %{entry | waiters: [from | entry.waiters]}
            {:noreply, %{state | inflight: Map.put(state.inflight, flight_key, entry)}}
        end
    end
  end

  def handle_call({:done, table, key, value}, _from, state) do
    {tid, state} = ensure_table(table, state)
    :ets.insert(tid, {key, value})

    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, {:value, value}) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
  end

  def handle_call({:fail, table, key}, _from, state) do
    flight_key = {table, key}

    case Map.pop(state.inflight, flight_key) do
      {nil, _} ->
        {:reply, :ok, state}

      {entry, inflight} ->
        Process.demonitor(entry.mref, [:flush])
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:reply, :ok, %{state | inflight: inflight}}
    end
  end

  def handle_call({:invalidate, table, key}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete(tid, key)
    end

    {:reply, :ok, state}
  end

  def handle_call({:invalidate_all, table}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete_all_objects(tid)
    end

    {:reply, :ok, state}
  end