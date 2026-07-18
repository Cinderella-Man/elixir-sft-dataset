  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key), do: GenServer.call(server, {:get, key})