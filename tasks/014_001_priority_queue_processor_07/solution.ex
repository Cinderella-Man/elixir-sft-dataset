  def status(server) do
    GenServer.call(server, :status)
  end