@impl true
def handle_call({:register, name, pid, interval_ms, on_timeout_fn}, _from, state) do
  state = cancel_entry(state, name)

  ref = make_ref()
  timer_ref = Process.send_after(self(), {:timeout, name, ref}, interval_ms)

  entry = %{
    pid: pid,
    interval_ms: interval_ms,
    on_timeout_fn: on_timeout_fn,
    ref: ref,
    timer_ref: timer_ref
  }

  {:reply, :ok, Map.put(state, name, entry)}
end

@impl true
def handle_call({:heartbeat, name}, _from, state) do
  case Map.fetch(state, name) do
    {:ok, entry} ->
      _ = Process.cancel_timer(entry.timer_ref)
      ref = make_ref()
      timer_ref = Process.send_after(self(), {:timeout, name, ref}, entry.interval_ms)
      entry = %{entry | ref: ref, timer_ref: timer_ref}
      {:reply, :ok, Map.put(state, name, entry)}

    :error ->
      {:reply, :ok, state}
  end
end

@impl true
def handle_call({:unregister, name}, _from, state) do
  {:reply, :ok, cancel_entry(state, name)}
end