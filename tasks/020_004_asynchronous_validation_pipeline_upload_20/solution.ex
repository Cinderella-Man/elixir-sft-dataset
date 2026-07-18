  @doc """
  Returns all records currently held by the store.
  """
  @spec list(GenServer.server()) :: [map()]
  def list(server), do: GenServer.call(server, :list)