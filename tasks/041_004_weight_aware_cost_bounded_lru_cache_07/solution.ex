  def put(name, key, value, weight) do
    GenServer.call(name, {:put, key, value, weight})
  end