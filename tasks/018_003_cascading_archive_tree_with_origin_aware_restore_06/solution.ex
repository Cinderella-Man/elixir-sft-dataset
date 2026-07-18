  def create_folder(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_folder, attrs})
  end