  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end