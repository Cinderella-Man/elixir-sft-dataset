  @doc "Blocks until the queue is empty and no tasks are actively being processed."
  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end