  @impl true
  def handle_call({:insert, s, f}, _from, state) do
    id = state.next_id
    tree = t_insert(state.tree, s, f, id)

    new_state = %{
      state
      | tree: tree,
        next_id: id + 1,
        entries: Map.put(state.entries, id, {s, f})
    }

    {:reply, {:ok, id}, new_state}
  end

  def handle_call({:remove, id}, _from, state) do
    case Map.fetch(state.entries, id) do
      {:ok, {s, f}} ->
        tree = t_delete(state.tree, s, f, id)
        {:reply, :ok, %{state | tree: tree, entries: Map.delete(state.entries, id)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:overlapping, qs, qf}, _from, state) do
    {:reply, Enum.sort(t_overlapping(state.tree, qs, qf, [])), state}
  end

  def handle_call({:enclosing, point}, _from, state) do
    {:reply, Enum.sort(t_enclosing(state.tree, point, [])), state}
  end

  def handle_call({:stab_count, point}, _from, state) do
    {:reply, t_stab_count(state.tree, point, 0), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end