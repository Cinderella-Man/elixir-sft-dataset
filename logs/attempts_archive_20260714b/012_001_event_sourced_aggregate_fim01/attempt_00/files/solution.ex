  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end