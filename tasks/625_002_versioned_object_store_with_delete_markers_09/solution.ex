  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end