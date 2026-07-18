  def create_file(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_file, attrs})
  end