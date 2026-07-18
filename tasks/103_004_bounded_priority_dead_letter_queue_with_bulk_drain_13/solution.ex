  def drain(server, queue_name, handler_fn, count)
      when is_function(handler_fn, 1) and is_integer(count) and count >= 0 do
    GenServer.call(server, {:drain, queue_name, handler_fn, count})
  end