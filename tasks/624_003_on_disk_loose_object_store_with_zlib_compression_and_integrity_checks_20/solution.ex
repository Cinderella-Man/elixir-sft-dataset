  @doc """
  Returns a sorted list of the hex SHA-1 hashes of every object on disk.
  """
  @spec list_objects(server()) :: [hash()]
  def list_objects(server) do
    GenServer.call(server, :list_objects)
  end