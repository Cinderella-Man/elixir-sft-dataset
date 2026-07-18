  @doc """
  Returns raw samples for series matching `metric_name` and `label_matchers`.

  A series matches when it contains all key/value pairs in `label_matchers`
  (extra labels are allowed); an empty map matches every series with the metric
  name. The result is a list of `{labels, points}` tuples where `points` is
  sorted ascending by timestamp and filtered to `start_ts <= ts <= end_ts`.
  Series with no point in range are omitted.
  """
  @spec query(server(), String.t(), labels(), range()) :: [{labels(), [point()]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end