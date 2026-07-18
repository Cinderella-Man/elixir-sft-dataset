  @doc "Returns whether a team identified by `team_id` exists."
  @spec team_exists?(server(), term()) :: boolean()
  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})