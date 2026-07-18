  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {cur_state, cur_version} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {cur_state, cur_version})
    {:reply, {:ok, cur_state, cur_version}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {cur_state, cur_version}} ->
        {:reply, {:ok, cur_state, cur_version}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event, expected_version}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {cur_state, cur_version}} ->
        do_transition(state, entity_id, event, expected_version, cur_state, cur_version)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    rows = load_history(state.repo, entity_id)
    {:reply, {:ok, rows}, state}
  end