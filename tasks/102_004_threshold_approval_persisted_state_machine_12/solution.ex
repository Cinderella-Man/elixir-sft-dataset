  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {current_state, approvals} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {current_state, approvals})

    {:reply, {:ok, current_state, approvals}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {current_state, approvals}} ->
        {:reply, {:ok, current_state, approvals}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {current_state, approvals}} ->
        do_transition(entity_id, event, current_state, approvals, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    {:reply, {:ok, fetch_history(state.repo, entity_id)}, state}
  end