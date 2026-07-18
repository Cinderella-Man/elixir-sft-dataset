  @doc """
  Returns whether `user_id` is a member of `team_id`.
  """
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end