  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end