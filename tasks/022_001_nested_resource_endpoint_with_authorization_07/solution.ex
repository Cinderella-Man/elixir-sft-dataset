  @doc "Creates a team `team_id`. Returns `:ok` or `{:error, reason}`."
  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})