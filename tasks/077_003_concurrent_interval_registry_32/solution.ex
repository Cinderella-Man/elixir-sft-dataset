  @doc """
  Returns the sorted list of stored intervals that contain `point`.
  """
  @spec enclosing(GenServer.server(), integer()) :: [interval()]
  def enclosing(server, point) when is_integer(point) do
    GenServer.call(server, {:enclosing, point})
  end