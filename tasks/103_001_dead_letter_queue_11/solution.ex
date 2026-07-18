  def retry(server, queue_name, message_id, handler_fn)
      when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end