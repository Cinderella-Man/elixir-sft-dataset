  def query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms) do
    request =
      {:query_range, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms}

    GenServer.call(server, request)
  end