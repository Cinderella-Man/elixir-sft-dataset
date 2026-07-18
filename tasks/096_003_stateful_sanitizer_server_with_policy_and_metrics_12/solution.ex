  @doc """
  Return the current metrics map.
  """
  @spec metrics(GenServer.server()) :: metrics()
  def metrics(server), do: GenServer.call(server, :metrics)