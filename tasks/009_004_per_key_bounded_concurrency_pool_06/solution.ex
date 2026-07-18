  def execute(server, key, func) when is_function(func, 0) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end