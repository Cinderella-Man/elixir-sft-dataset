  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end