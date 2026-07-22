  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    num_shards = Keyword.fetch!(opts, :num_shards)
    max_size = Keyword.fetch!(opts, :max_size)

    unless is_integer(num_shards) and num_shards > 0 do
      raise ArgumentError, ":num_shards must be a positive integer, got: #{inspect(num_shards)}"
    end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    routing =
      :ets.new(routing_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    :ets.insert(routing, {:__num_shards__, num_shards})

    shards =
      for i <- 0..(num_shards - 1) do
        shard = shard_name_for_index(name, i)
        {:ok, pid} = LRUCacheSharded.Shard.start_link(name: shard, max_size: max_size)
        {shard, pid}
      end

    {:ok, %{name: name, routing: routing, shards: shards}}
  end