  @doc "Returns a `MapSet` of all keys associated with `value` (empty if none)."
  @spec get_by_value(GenServer.server(), term()) :: MapSet.t()
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})