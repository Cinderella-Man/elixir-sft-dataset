  @doc """
  Grants permission for `{resource, action}` directly to `role`.

  The role must exist, otherwise returns `{:error, :unknown_role}`. Idempotent.
  Returns `:ok` on success.
  """
  @spec grant(GenServer.server(), atom(), atom(), atom()) :: :ok | {:error, :unknown_role}
  def grant(server, role, resource, action) do
    GenServer.call(server, {:grant, role, resource, action})
  end