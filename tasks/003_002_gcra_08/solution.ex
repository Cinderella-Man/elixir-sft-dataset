  def acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)
      when is_number(rate_per_sec) and rate_per_sec > 0 and
             is_integer(burst_size) and burst_size > 0 and
             is_integer(tokens) and tokens > 0 do
    GenServer.call(server, {:acquire, bucket_name, rate_per_sec, burst_size, tokens})
  end