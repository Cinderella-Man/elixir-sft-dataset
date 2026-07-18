  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end