  def get(server, name, type, period)
      when type in [:wma, :hma] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end