  # :start — hydrate from DB (or seed with :pending), cache in map
  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_latest_state(state.repo, entity_id)
    new_entities = Map.put(state.entities, entity_id, current)
    {:reply, {:ok, current}, %{state | entities: new_entities}}
  end

  # :get_state — pure in-memory lookup
  @impl true
  def handle_call({:get_state, entity_id}, _from, state) do
    reply =
      case Map.fetch(state.entities, entity_id) do
        {:ok, current} -> {:ok, current}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  # :transition — serialised call; in-memory update only after DB write succeeds
  @impl true
  def handle_call({:transition, entity_id, event}, _from, state) do
    with {:found, current} <- entity_lookup(state.entities, entity_id),
         {:valid, next_state} <- resolve_transition(current, event),
         {:persisted, _record} <- persist(state.repo, entity_id, event, current, next_state) do
      new_entities = Map.put(state.entities, entity_id, next_state)
      {:reply, {:ok, next_state}, %{state | entities: new_entities}}
    else
      {:not_found} -> {:reply, {:error, :not_found}, state}
      {:invalid} -> {:reply, {:error, :invalid_transition}, state}
      {:db_error, reason} -> {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  # :history — fetch rows from DB, deserialise string columns back to atoms
  @impl true
  def handle_call({:history, entity_id}, _from, state) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at]
      )

    result =
      try do
        rows = state.repo.all(query)

        history =
          Enum.map(rows, fn row ->
            %{
              event: String.to_existing_atom(row.event),
              from_state: String.to_existing_atom(row.from_state),
              to_state: String.to_existing_atom(row.to_state),
              inserted_at: row.inserted_at
            }
          end)

        {:ok, history}
      rescue
        e -> {:error, Exception.message(e)}
      end

    {:reply, result, state}
  end