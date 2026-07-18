  @doc "Returns whether the association `{key, value}` is currently present."
  @spec member?(GenServer.server(), term(), term()) :: boolean()
  def member?(name, key, value), do: GenServer.call(name, {:member?, key, value})