  def delete_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:delete_object, bucket, key, opts})
  end