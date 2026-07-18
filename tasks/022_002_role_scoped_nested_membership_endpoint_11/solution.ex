  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    {:reply, :ok, %{state | teams: Map.put_new(state.teams, team_id, %{})}}
  end

  def handle_call({:add_member, team_id, user_id, role}, _from, state) do
    members = state.teams |> Map.get(team_id, %{}) |> Map.put(user_id, role)
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
    {:reply, Map.has_key?(Map.get(state.teams, team_id, %{}), user_id), state}
  end

  def handle_call({:role_of, team_id, user_id}, _from, state) do
    reply =
      with {:ok, members} <- Map.fetch(state.teams, team_id),
           {:ok, role} <- Map.fetch(members, user_id) do
        {:ok, role}
      else
        :error -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, members} ->
        list = Enum.map(members, fn {uid, role} -> %{user_id: uid, role: role} end)
        {:reply, {:ok, list}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id, role}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if Map.has_key?(members, user_id) do
          {:reply, {:error, :conflict}, state}
        else
          teams = Map.put(state.teams, team_id, Map.put(members, user_id, role))
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        end
    end
  end

  def handle_call({:remove_member_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if Map.has_key?(members, user_id) do
          teams = Map.put(state.teams, team_id, Map.delete(members, user_id))
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        else
          {:reply, {:error, :not_member}, state}
        end
    end
  end