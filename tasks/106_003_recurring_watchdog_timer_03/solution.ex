@impl true
def handle_call({:register, name, pid, interval_ms, fun}, _from, state) do
  state = cancel_entry(state, name)
  ref = make_ref()
  timer = Process.send_after(self(), {:tick, name, ref}, interval_ms)

  entry = %{
    pid: pid,
    interval_ms: interval_ms,
    fun: fun,
    status: :healthy,
    ref: ref,
    timer: timer
  }

  {:reply, :ok, Map.put(state, name, entry)}
end

def handle_call({:heartbeat, name}, _from, state) do
  case Map.fetch(state, name) do
    {:ok, entry} ->
      _ = Process.cancel_timer(entry.timer)
      ref = make_ref()
      timer = Process.send_after(self(), {:tick, name, ref}, entry.interval_ms)
      {:reply, :ok, Map.put(state, name, %{entry | status: :healthy, ref: ref, timer: timer})}

    :error ->
      {:reply, :ok, state}
  end
end

def handle_call({:unregister, name}, _from, state) do
  {:reply, :ok, cancel_entry(state, name)}
end

def handle_call({:status, name}, _from, state) do
  case Map.fetch(state, name) do
    {:ok, entry} -> {:reply, {:ok, entry.status}, state}
    :error -> {:reply, {:error, :not_registered}, state}
  end
end