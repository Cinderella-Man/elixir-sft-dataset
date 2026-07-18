  @doc """
  Adds a user to a team directly (for seeding).

  Adding a not-yet-present user increments the team's version by 1; adding a
  user already present is a no-op that leaves the version unchanged.
  """
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end