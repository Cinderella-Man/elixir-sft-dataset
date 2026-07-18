  def list_versions(server, bucket, key) do
    GenServer.call(server, {:list_versions, bucket, key})
  end