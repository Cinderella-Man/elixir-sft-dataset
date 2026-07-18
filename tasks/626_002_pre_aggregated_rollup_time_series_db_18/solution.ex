  @doc """
  Queries rollup buckets for series matching `metric_name` and `label_matchers`.

  A series matches when it contains **all** key/value pairs in
  `label_matchers` (extra labels are allowed); an empty map matches every
  series with the given metric name. Returns a list of `{labels, buckets}`
  tuples where `buckets` is a list of `{bucket_start, stats}` sorted ascending
  by `bucket_start`, restricted to `start_ts <= bucket_start <= end_ts`.

  Series with no bucket in range are omitted entirely.
  """
  @spec query(
          GenServer.server(),
          metric_name(),
          labels(),
          {integer(), integer()}
        ) :: [{labels(), [{bucket_start(), stats()}]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end