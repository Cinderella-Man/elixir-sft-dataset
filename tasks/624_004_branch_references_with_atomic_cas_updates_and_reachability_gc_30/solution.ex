  @doc """
  Returns a map of branch name to commit hash for all branches.
  """
  @spec list_branches(GenServer.server()) :: %{optional(String.t()) => hash}
  def list_branches(server) do
    GenServer.call(server, :list_branches)
  end