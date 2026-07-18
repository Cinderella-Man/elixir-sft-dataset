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
    team = Map.get(state.teams, team_id, new_team())
    {:reply, :ok, put_team(state, team_id, team)}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    team = Map.get(state.teams, team_id, new_team())

    team = %{
      team
      | members: MapSet.put(team.members, user_id),
        invitations: MapSet.delete(team.invitations, user_id)
    }

    {:reply, :ok, put_team(state, team_id, team)}
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
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> MapSet.member?(team.members, user_id)
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:is_invited?, team_id, user_id}, _from, state) do
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> MapSet.member?(team.invitations, user_id)
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, MapSet.to_list(team.members)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_invitations, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, MapSet.to_list(team.invitations)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:invite_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        cond do
          MapSet.member?(team.members, user_id) ->
            {:reply, {:error, :conflict}, state}

          MapSet.member?(team.invitations, user_id) ->
            {:reply, {:error, :already_invited}, state}

          true ->
            team = %{team | invitations: MapSet.put(team.invitations, user_id)}
            {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        end
    end
  end

  def handle_call({:accept_invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        if MapSet.member?(team.invitations, user_id) do
          team = %{
            team
            | invitations: MapSet.delete(team.invitations, user_id),
              members: MapSet.put(team.members, user_id)
          }

          {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        else
          {:reply, {:error, :no_invitation}, state}
        end
    end
  end

  def handle_call({:decline_invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        if MapSet.member?(team.invitations, user_id) do
          team = %{team | invitations: MapSet.delete(team.invitations, user_id)}
          {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        else
          {:reply, {:error, :no_invitation}, state}
        end
    end
  end