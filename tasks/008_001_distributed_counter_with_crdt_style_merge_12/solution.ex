  @impl GenServer
  def handle_call({:increment, node_id, amount}, _from, state) do
    new_state = update_in(state, [:p, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call({:decrement, node_id, amount}, _from, state) do
    new_state = update_in(state, [:n, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call(:value, _from, state) do
    {:reply, compute_value(state), state}
  end

  def handle_call({:merge, remote}, _from, local) do
    {:reply, :ok, merge_states(local, remote)}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end