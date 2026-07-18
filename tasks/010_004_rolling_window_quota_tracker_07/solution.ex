  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end