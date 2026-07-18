  def update(server, session_id, new_data) do
    GenServer.call(server, {:update, session_id, new_data})
  end