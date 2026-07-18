  @doc "Stores a user identified by `id` with the given bearer `token`."
  @spec create_user(server(), term(), String.t()) :: :ok
  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})