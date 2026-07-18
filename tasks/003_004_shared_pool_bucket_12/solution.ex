  def key_level(server, bucket_name, key_capacity, key_refill_rate)
      when is_integer(key_capacity) and key_capacity > 0 and
             is_number(key_refill_rate) and key_refill_rate > 0 do
    GenServer.call(
      server,
      {:key_level, bucket_name, key_capacity, key_refill_rate * 1.0}
    )
  end