  def put(name, key, value, priority) do
    GenServer.call(name, {:put, key, value, priority})
  end