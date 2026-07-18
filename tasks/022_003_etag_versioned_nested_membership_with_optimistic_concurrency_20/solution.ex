  @doc """
  Stores a user with the given `id` and bearer `token`.
  """
  @spec create_user(server(), String.t(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end