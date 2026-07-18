  def push(server, queue_name, dedup_key, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, dedup_key, message, error_reason, metadata})
  end