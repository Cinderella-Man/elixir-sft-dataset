  def add_inheritance(server, child, parent) do
    GenServer.call(server, {:add_inheritance, child, parent})
  end