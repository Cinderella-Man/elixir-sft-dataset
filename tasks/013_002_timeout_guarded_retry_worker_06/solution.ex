  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end