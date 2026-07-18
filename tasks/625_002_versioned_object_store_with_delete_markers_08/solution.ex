  def put_object(server, bucket, key, data, metadata \\ %{}) do
    GenServer.call(server, {:put_object, bucket, key, data, metadata})
  end