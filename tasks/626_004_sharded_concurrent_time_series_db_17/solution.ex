  @doc """
  Inserts a single `{timestamp, value}` point into the series identified by
  `metric_name` and `labels`, routing it to the owning shard.
  """
  @spec insert(server(), term(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end