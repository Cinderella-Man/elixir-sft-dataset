  def register(server, account_id) do
    GenServer.call(server, {:register, account_id})
  end