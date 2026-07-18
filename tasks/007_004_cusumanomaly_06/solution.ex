  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end