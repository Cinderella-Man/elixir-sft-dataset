  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
           is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end