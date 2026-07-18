  @doc """
  Returns the list of keys currently tracked by the server.

  A key appears only while it still has at least one bucket retained in state.
  After a cleanup removes all of a key's buckets, the key is dropped and will
  not be returned here. Intended for introspection and tests, this lets callers
  observe cleanup behavior through the public API rather than internal state.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end