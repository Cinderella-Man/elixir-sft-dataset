  @doc """
  Registers `role`. Idempotent — adding an existing role is a no-op. Returns `:ok`.
  """
  @spec add_role(GenServer.server(), atom()) :: :ok
  def add_role(server, role), do: GenServer.call(server, {:add_role, role})