  def delete_version(server, bucket, key, version_id) do
    GenServer.call(server, {:delete_version, bucket, key, version_id})
  end