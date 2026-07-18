  @doc """
  Marks `element` as removed at the given `timestamp`.

  If the element already has a recorded remove timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec remove(server(), element(), timestamp()) :: :ok
  def remove(server, element, timestamp) do
    validate_timestamp!(timestamp, :remove)
    GenServer.call(server, {:remove, element, timestamp})
  end