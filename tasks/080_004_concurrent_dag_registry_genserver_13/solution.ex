  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), t()) :: {:reply, term(), t()}
  def handle_call({:add_vertex, vertex}, _from, state) do
    {:reply, :ok, do_add_vertex(state, vertex)}
  end

  def handle_call({:add_edge, from, to}, _from, state) do
    case do_add_edge(state, from, to) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:topological_sort, _from, state) do
    {:reply, {:ok, topo_order(state)}, state}
  end

  def handle_call({:predecessors, vertex}, _from, state) do
    {:reply, state.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list(), state}
  end

  def handle_call({:successors, vertex}, _from, state) do
    {:reply, state.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list(), state}
  end

  def handle_call(:vertices, _from, state) do
    {:reply, MapSet.to_list(state.vertices), state}
  end