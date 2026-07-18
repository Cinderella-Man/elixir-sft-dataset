  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, [])
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    members = Map.get(state.teams, team_id, [])
    members = if user_id in members, do: members, else: members ++ [user_id]
    {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, members)}}
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    case Map.fetch(state.tokens, token) do
      {:ok, user_id} -> {:reply, {:ok, user_id}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    {:reply, user_id in Map.get(state.teams, team_id, []), state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, members} -> {:reply, {:ok, members}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if user_id in members do
          {:reply, {:error, :conflict}, state}
        else
          teams = Map.put(state.teams, team_id, members ++ [user_id])
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        end
    end
  end