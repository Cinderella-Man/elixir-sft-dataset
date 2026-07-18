  @doc """
  Adds `element` to the set with the given `timestamp`.

  If the element already has a recorded add timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec add(server(), element(), timestamp()) :: :ok
  def add(server, element, timestamp) do
    validate_timestamp!(timestamp, :add)
    GenServer.call(server, {:add, element, timestamp})
  end