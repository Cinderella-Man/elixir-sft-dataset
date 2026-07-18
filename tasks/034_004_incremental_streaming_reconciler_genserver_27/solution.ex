  @doc """
  Stops the server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end