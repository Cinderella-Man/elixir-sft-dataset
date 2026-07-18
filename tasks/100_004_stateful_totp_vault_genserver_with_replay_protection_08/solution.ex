  def current_code(server, account_id, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    GenServer.call(server, {:current_code, account_id, time})
  end