  @impl GenServer
  def handle_call({:add, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:adds, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:remove, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:removes, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:member?, element}, _from, state) do
    {:reply, element_present?(state, element), state}
  end

  def handle_call(:members, _from, state) do
    {:reply, compute_members(state), state}
  end

  def handle_call({:merge, remote}, _from, local) do
    {:reply, :ok, merge_states(local, remote)}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end