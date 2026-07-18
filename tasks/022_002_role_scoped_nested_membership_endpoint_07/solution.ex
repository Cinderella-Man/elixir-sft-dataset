  @doc "Creates an empty team identified by `team_id`."
  @spec create_team(server(), term()) :: :ok
  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})