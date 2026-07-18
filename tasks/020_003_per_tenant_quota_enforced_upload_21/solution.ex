  @doc """
  Returns all stored metadata records.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)