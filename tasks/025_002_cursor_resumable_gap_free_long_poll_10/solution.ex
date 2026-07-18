  @impl true
  def handle_call({:subscribe, user_id, pid}, _from, state) do
    ref = Process.monitor(pid)
    subs = Map.update(state.subs, user_id, [pid], fn pids -> [pid | pids] end)
    mons = Map.put(state.mons, ref, {user_id, pid})
    {:reply, :ok, %{state | subs: subs, mons: mons}}
  end

  def handle_call({:publish, user_id, payload}, _from, state) do
    seq = Map.get(state.seq, user_id, 0) + 1
    entry = {seq, payload}

    # Newest kept at the head; retain only the most recent buffer_size entries.
    buf =
      [entry | Map.get(state.buf, user_id, [])]
      |> Enum.take(state.buffer_size)

    state = %{
      state
      | seq: Map.put(state.seq, user_id, seq),
        buf: Map.put(state.buf, user_id, buf)
    }

    for pid <- Map.get(state.subs, user_id, []) do
      send(pid, {:notification, seq, payload})
    end

    {:reply, {:ok, seq}, state}
  end

  def handle_call({:events_since, user_id, cursor}, _from, state) do
    events =
      state.buf
      |> Map.get(user_id, [])
      |> Enum.reverse()
      |> Enum.filter(fn {seq, _payload} -> seq > cursor end)

    {:reply, events, state}
  end