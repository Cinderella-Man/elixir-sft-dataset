  def set_ttl(server, bucket, key, ttl_ms) do
    GenServer.call(server, {:set_ttl, bucket, key, ttl_ms})
  end