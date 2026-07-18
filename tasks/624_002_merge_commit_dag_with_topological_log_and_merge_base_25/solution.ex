  def merge_base(server, hash_a, hash_b)
      when is_binary(hash_a) and is_binary(hash_b) do
    GenServer.call(server, {:merge_base, hash_a, hash_b})
  end