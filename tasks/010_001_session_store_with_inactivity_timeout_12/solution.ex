  @impl GenServer
  def handle_call({:create, session_data}, _from, state) do
    session_id = generate_session_id()
    now = state.clock.()

    session = %{data: session_data, last_active: now}
    new_sessions = Map.put(state.sessions, session_id, session)

    {:reply, {:ok, session_id}, %{state | sessions: new_sessions}}
  end

  def handle_call({:get, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, session.data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update, session_id, new_data}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | data: new_data, last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, new_data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:touch, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, :ok, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:destroy, session_id}, _from, state) do
    new_sessions = Map.delete(state.sessions, session_id)
    {:reply, :ok, %{state | sessions: new_sessions}}
  end