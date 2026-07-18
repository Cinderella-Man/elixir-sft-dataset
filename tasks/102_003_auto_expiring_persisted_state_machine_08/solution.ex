  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end