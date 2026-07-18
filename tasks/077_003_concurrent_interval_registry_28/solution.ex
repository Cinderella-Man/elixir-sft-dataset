  @doc """
  Stops the registry `server`.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)