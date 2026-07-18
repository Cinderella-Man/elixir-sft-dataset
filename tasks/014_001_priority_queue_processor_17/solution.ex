  @doc """
  Blocks until the queue is empty and the processor is idle.
  """
  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end