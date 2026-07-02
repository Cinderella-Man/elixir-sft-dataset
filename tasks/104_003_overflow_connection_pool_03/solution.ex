@impl true
def handle_call({:checkout, timeout}, from, state) do
  {pid, _tag} = from

  cond do
    state.available != [] ->
      [conn | rest] = state.available
      {:reply, {:ok, conn}, assign(conn, pid, %{state | available: rest})}

    state.total < state.size + state.max_overflow ->
      conn = state.create.()
      {:reply, {:ok, conn}, assign(conn, pid, %{state | total: state.total + 1})}

    timeout == 0 ->
      {:reply, {:error, :timeout}, state}

    true ->
      mon = Process.monitor(pid)
      timer = Process.send_after(self(), {:waiter_timeout, mon}, timeout)
      waiter = %{from: from, pid: pid, mon: mon, timer: timer}
      {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
  end
end

def handle_call({:checkin, conn}, _from, state) do
  case Map.pop(state.in_use, conn) do
    {{_pid, mon}, in_use} ->
      Process.demonitor(mon, [:flush])
      {:reply, :ok, release(conn, %{state | in_use: in_use})}

    {nil, _in_use} ->
      {:reply, :ok, state}
  end
end

def handle_call(:stats, _from, state) do
  {:reply,
   %{
     available: length(state.available),
     in_use: map_size(state.in_use),
     total: state.total,
     size: state.size,
     max_overflow: state.max_overflow,
     overflow: max(0, state.total - state.size)
   }, state}
end