  @doc "The configured number of shards."
  @spec num_shards(name()) :: pos_integer()
  def num_shards(name) do
    [{:__num_shards__, n}] = :ets.lookup(routing_table_name(name), :__num_shards__)
    n
  end