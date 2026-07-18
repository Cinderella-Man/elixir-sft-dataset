  @doc "Removes `value` and all of its associations. Returns `:ok`."
  @spec delete_value(GenServer.server(), term()) :: :ok
  def delete_value(name, value), do: GenServer.call(name, {:delete_value, value})