  def rename_node(server, id, new_name) do
    GenServer.call(server, {:rename_node, id, new_name})
  end