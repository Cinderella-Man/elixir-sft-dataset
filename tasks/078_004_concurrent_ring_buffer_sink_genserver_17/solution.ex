  @doc """
  Atomically returns all live items (oldest → newest) and empties the buffer.
  """
  @spec flush(GenServer.server()) :: list()
  def flush(server), do: GenServer.call(server, :flush)