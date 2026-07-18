  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end