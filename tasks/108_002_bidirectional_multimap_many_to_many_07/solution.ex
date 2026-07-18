  @doc "Returns a `MapSet` of all values associated with `key` (empty if none)."
  @spec get_by_key(GenServer.server(), term()) :: MapSet.t()
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})