  def consume(server, account_id, code, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    GenServer.call(server, {:consume, account_id, normalize_code(code), time, window})
  end