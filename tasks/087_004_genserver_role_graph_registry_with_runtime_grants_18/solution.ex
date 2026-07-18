  @doc """
  Returns `true` if `role`, or any role it inherits transitively, has a direct
  grant for `{resource, action}`; otherwise `false`.

  Returns `false` for an unknown role.
  """
  @spec can?(GenServer.server(), atom(), atom(), atom()) :: boolean()
  def can?(server, role, resource, action) do
    GenServer.call(server, {:can?, role, resource, action})
  end