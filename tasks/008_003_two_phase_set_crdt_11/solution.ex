  @impl GenServer
  def handle_call({:add, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(removed, element) do
      {:reply, {:error, :tombstoned}, state}
    else
      {:reply, :ok, %{state | added: MapSet.put(added, element)}}
    end
  end

  def handle_call({:remove, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(added, element) and not MapSet.member?(removed, element) do
      {:reply, :ok, %{state | removed: MapSet.put(removed, element)}}
    else
      {:reply, {:error, :not_a_member}, state}
    end
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