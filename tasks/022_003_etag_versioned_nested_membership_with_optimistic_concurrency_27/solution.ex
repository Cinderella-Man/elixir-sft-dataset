  @doc """
  Returns `{:ok, list_of_user_ids}` for the team, or `{:error, :not_found}`.
  """
  @spec list_members(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end