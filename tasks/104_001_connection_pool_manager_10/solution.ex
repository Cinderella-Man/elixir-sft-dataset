  @impl true
  def handle_info({:waiter_timeout, mon}, state) do
    case remove_waiter_by_mon(state.waiters, mon) do
      {:ok, waiter, rest} ->
        Process.demonitor(waiter.mon, [:flush])
        GenServer.reply(waiter.from, {:error, :timeout})
        {:noreply, %{state | waiters: rest}}

      :error ->
        # Already served (and removed from the queue) before the timer fired.
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case find_conn_by_ref(state.in_use, ref) do
      {:ok, conn} ->
        # An owner died while holding a connection — reclaim it.
        in_use = Map.delete(state.in_use, conn)
        {:noreply, place_connection(conn, %{state | in_use: in_use})}

      :error ->
        # Maybe a waiting caller died before being served — drop it.
        case remove_waiter_by_mon(state.waiters, ref) do
          {:ok, waiter, rest} ->
            _ = Process.cancel_timer(waiter.timer)
            {:noreply, %{state | waiters: rest}}

          :error ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}