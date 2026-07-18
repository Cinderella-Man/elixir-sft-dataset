  @impl GenServer
  def handle_call({:add, element, node_id}, _from, state) do
    # Increment the clock for this node
    new_counter = Map.get(state.clock, node_id, 0) + 1
    new_clock = Map.put(state.clock, node_id, new_counter)
    tag = {node_id, new_counter}

    # Add the tag to the element's entry set
    new_entries =
      Map.update(state.entries, element, MapSet.new([tag]), fn existing ->
        MapSet.put(existing, tag)
      end)

    {:reply, :ok, %{state | entries: new_entries, clock: new_clock}}
  end

  def handle_call({:remove, element}, _from, state) do
    case Map.fetch(state.entries, element) do
      {:ok, tags} when tags != %MapSet{} ->
        if MapSet.size(tags) == 0 do
          {:reply, {:error, :not_a_member}, state}
        else
          # Move all current tags to tombstones
          new_tombstones = MapSet.union(state.tombstones, tags)
          new_entries = Map.delete(state.entries, element)
          {:reply, :ok, %{state | entries: new_entries, tombstones: new_tombstones}}
        end

      _ ->
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