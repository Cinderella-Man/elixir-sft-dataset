  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    state = %{
      state
      | users: Map.put(state.users, id, token),
        tokens: Map.put(state.tokens, token, id)
    }

    {:reply, :ok, state}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, %{members: [], version: 0})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, :ok, state}
        else
          team = %{team | members: members ++ [user_id], version: version + 1}
          {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, team)}}
        end

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    {:reply, Map.fetch(state.tokens, token), state}
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    member? =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> user_id in members
        :error -> false
      end

    {:reply, member?, state}
  end

  def handle_call({:get_version, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{version: version}} -> {:ok, version}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> {:ok, members}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:add_member_safe, team_id, user_id, expected_version}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{version: version}} when version != expected_version ->
        {:reply, {:error, :stale}, state}

      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, {:error, :conflict}, state}
        else
          new_version = version + 1
          team = %{team | members: members ++ [user_id], version: new_version}
          state = %{state | teams: Map.put(state.teams, team_id, team)}
          {:reply, {:ok, user_id, new_version}, state}
        end
    end
  end