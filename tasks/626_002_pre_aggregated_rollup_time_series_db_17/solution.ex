  @doc """
  Folds a single data point into the appropriate rollup bucket.

  The point is attributed to the bucket identified by
  `div(timestamp, bucket_duration_ms) * bucket_duration_ms` for the series
  `{metric_name, Enum.sort(Map.to_list(labels))}`. No raw point is stored;
  only the bucket's accumulator is updated. Always returns `:ok`.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end