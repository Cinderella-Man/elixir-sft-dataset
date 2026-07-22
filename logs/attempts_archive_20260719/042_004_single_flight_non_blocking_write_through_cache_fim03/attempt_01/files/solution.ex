  def handle_call({:invalidate_all, table}, _from, state) do
    case Map.get(state.tables, table) do
      nil -> :ok
      tid -> :ets.delete_all_objects(tid)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, mref, :process, _pid, _reason}, state) do
    case Enum.find(state.inflight, fn {_k, entry} -> entry.mref == mref end) do
      nil ->
        {:noreply, state}

      {flight_key, entry} ->
        Enum.each(entry.waiters, fn w -> GenServer.reply(w, :retry) end)
        {:noreply, %{state | inflight: Map.delete(state.inflight, flight_key)}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    pid = self()

    Enum.each(state.tables, fn {table, tid} ->
      :persistent_term.erase({__MODULE__, pid, table})
      :ets.delete(tid)
    end)

    :ok
  end