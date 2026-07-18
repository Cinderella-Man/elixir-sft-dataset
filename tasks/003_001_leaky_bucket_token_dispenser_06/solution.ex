  def acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1) do
    GenServer.call(server, {:acquire, bucket_name, capacity, refill_rate, tokens})
  end