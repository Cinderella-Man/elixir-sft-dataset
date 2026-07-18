  @doc """
  Like `query/4`, but aggregates each matched series into fixed windows.

  The range `[start_ts, end_ts)` is split into non-overlapping windows of
  width `step_ms`. For each window, the points whose timestamps fall in
  `[window_start, window_start + step_ms)` are reduced with `aggregation`
  (`:sum`, `:avg` or `:max`); empty windows are omitted. Each result is
  `{labels, agg_points}` with `agg_points` a list of
  `{window_start, aggregated_value}` sorted by window start. Series whose
  windows are all empty are dropped.
  """
  @spec query_agg(
          server(),
          term(),
          labels(),
          {integer(), integer()},
          :sum | :avg | :max,
          pos_integer()
        ) :: [series_result()]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    msg = {:query_agg, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms}
    GenServer.call(server, msg)
  end