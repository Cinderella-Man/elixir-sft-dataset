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