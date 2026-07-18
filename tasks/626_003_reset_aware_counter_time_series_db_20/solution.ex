  @doc """
  Inserts a single sample for the given metric and label set.

  The point is stored into the chunk identified by
  `div(timestamp, chunk_duration_ms) * chunk_duration_ms` and kept sorted by
  timestamp within that chunk. Always returns `:ok`.
  """
  @spec insert(server(), String.t(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end