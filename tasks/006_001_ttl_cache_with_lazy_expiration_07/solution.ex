  @doc "Retrieves the value for `key`, returning `{:ok, value}` or `:miss`."
  @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end