  @doc """
  Removes a direct `{resource, action}` grant from `role`.

  Only the role's own grant is removed, not inherited ones. Returns `:ok` even
  if the grant was not present.
  """
  @spec revoke(GenServer.server(), atom(), atom(), atom()) :: :ok
  def revoke(server, role, resource, action) do
    GenServer.call(server, {:revoke, role, resource, action})
  end