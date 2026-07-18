  def get_object_version(server, bucket, key, version_id) do
    GenServer.call(server, {:get_object_version, bucket, key, version_id})
  end