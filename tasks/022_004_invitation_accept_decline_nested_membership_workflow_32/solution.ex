  @doc """
  Returns `true` if the user has a pending invitation for the team, else
  `false`.
  """
  @spec is_invited?(server(), String.t(), String.t()) :: boolean()
  def is_invited?(server, team_id, user_id) do
    GenServer.call(server, {:is_invited?, team_id, user_id})
  end