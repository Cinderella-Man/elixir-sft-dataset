  @spec put_team(state(), String.t(), map()) :: state()
  defp put_team(state, team_id, team) do
    %{state | teams: Map.put(state.teams, team_id, team)}
  end