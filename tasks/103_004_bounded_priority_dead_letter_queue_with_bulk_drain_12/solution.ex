  def push(server, queue_name, message, error_reason, metadata, priority)
      when is_map(metadata) and priority in [:high, :normal, :low] do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata, priority})
  end