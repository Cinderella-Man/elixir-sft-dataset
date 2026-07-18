  @doc """
  Deletes branch `name`. Returns `:ok`, or `{:error, :no_branch}` if it does
  not exist.
  """
  @spec delete_branch(GenServer.server(), String.t()) :: :ok | {:error, :no_branch}
  def delete_branch(server, name) when is_binary(name) do
    GenServer.call(server, {:delete_branch, name})
  end