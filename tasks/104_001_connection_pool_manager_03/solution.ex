  @impl true
  def handle_call({:checkout, timeout}, from, state) do
    {pid, _tag} = from

    cond do
      # 1. A connection is available — hand it out immediately.
      state.available != [] ->
        [conn | rest] = state.available
        state = assign(conn, pid, %{state | available: rest})
        {:reply, {:ok, conn}, state}

      # 2. Room to grow — lazily create a fresh connection.
      state.total < state.max ->
        conn = state.create.()
        state = assign(conn, pid, %{state | total: state.total + 1})
        {:reply, {:ok, conn}, state}

      # 3. At capacity, caller doesn't want to wait.
      timeout == 0 ->
        {:reply, {:error, :timeout}, state}

      # 4. At capacity — enqueue the caller as a waiter and reply later.
      true ->
        mon = Process.monitor(pid)
        timer = Process.send_after(self(), {:waiter_timeout, mon}, timeout)
        waiter = %{from: from, pid: pid, mon: mon, timer: timer}
        {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
    end
  end

  @impl true
  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.in_use, conn) do
      {{_pid, mon}, in_use} ->
        Process.demonitor(mon, [:flush])
        state = place_connection(conn, %{state | in_use: in_use})
        {:reply, :ok, state}

      {nil, _in_use} ->
        # Unknown / already-returned connection: place it as available anyway,
        # but only if it isn't already tracked, to avoid duplicates.
        state =
          if conn in state.available do
            state
          else
            place_connection(conn, state)
          end

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      available: length(state.available),
      in_use: map_size(state.in_use),
      total: state.total,
      max: state.max,
      min: state.min
    }

    {:reply, stats, state}
  end