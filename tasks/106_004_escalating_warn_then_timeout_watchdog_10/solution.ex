  @impl true
  def handle_call(
        {:register, name, pid, warn_ms, timeout_ms, warn_fn, timeout_fn},
        _from,
        state
      ) do
    state = cancel_entry(state, name)

    entry =
      arm(
        %{
          pid: pid,
          warn_ms: warn_ms,
          timeout_ms: timeout_ms,
          warn_fn: warn_fn,
          timeout_fn: timeout_fn
        },
        name
      )

    {:reply, :ok, Map.put(state, name, entry)}
  end

  def handle_call({:heartbeat, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} ->
        entry = entry |> disarm() |> arm(name)
        {:reply, :ok, Map.put(state, name, entry)}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok, cancel_entry(state, name)}
  end

  def handle_call({:phase, name}, _from, state) do
    case Map.fetch(state, name) do
      {:ok, entry} -> {:reply, {:ok, entry.phase}, state}
      :error -> {:reply, {:error, :not_registered}, state}
    end
  end