  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end