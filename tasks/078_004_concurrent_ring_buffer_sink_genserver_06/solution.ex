  @doc "Inserts `item`, overwriting the oldest when full. Returns `:ok`."
  @spec push(GenServer.server(), any()) :: :ok
  def push(server, item), do: GenServer.call(server, {:push, item})