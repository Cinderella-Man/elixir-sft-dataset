  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end