  @doc """
  Returns `{:ok, commit_hash}` for the commit branch `name` points at, or
  `{:error, :no_branch}` if there is no such branch.
  """
  @spec branch_head(GenServer.server(), String.t()) :: {:ok, hash} | {:error, :no_branch}
  def branch_head(server, name) when is_binary(name) do
    GenServer.call(server, {:branch_head, name})
  end