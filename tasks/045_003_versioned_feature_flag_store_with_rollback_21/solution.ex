  @doc """
  Reverts `flag` to its immediately preceding state by appending that state as
  a new version (history keeps growing).

  Returns `:ok` on success, `{:error, :no_previous_version}` when the flag has
  only one version, and `{:error, :unknown_flag}` when it was never set.
  """
  @spec rollback(atom()) :: :ok | {:error, :no_previous_version | :unknown_flag}
  def rollback(flag), do: GenServer.call(server(), {:rollback, flag})