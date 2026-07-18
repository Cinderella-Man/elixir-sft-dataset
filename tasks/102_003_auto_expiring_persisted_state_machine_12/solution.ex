  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)
    maybe_schedule(current, entity_id, state.ttl)
    new_states = Map.put(state.states, entity_id, current)
    {:reply, {:ok, current}, %{state | states: new_states}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      :error -> {:reply, {:error, :not_found}, state}
      {:ok, current} -> apply_transition(entity_id, current, event, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    repo = state.repo

    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          inserted_at: t.inserted_at
        }
      )

    rows = Enum.map(repo.all(query), &decode_history_row/1)
    {:reply, {:ok, rows}, state}
  end