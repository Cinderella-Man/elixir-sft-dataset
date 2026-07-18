  @doc """
  Insert a single data point into the store.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), timestamp(), value()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end