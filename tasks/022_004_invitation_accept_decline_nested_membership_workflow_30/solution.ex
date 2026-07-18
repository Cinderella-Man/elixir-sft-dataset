  @doc """
  Returns `true` if the team exists, otherwise `false`.
  """
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end