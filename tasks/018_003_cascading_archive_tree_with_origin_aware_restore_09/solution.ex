  def list_children(server, folder_id, opts \\ []) do
    GenServer.call(server, {:list_children, folder_id, include_archived?(opts)})
  end