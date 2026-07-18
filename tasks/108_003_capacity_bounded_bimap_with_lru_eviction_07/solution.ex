  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})