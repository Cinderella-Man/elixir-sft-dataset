  def delete_bucket(server, name) do
    GenServer.call(server, {:delete_bucket, name})
  end