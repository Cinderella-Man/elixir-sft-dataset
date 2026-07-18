  @doc """
  Returns `{:ok, version}` for the team, or `{:error, :not_found}`.
  """
  @spec get_version(server(), String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_version(server, team_id) do
    GenServer.call(server, {:get_version, team_id})
  end