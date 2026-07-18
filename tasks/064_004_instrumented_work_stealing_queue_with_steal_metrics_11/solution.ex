  defp build_metrics(worker_returns, worker_count) do
    zero = for i <- 0..(worker_count - 1), into: %{}, do: {i, 0}

    Enum.reduce(
      worker_returns,
      %{processed: zero, steals: zero, stolen: zero},
      fn r, metrics ->
        %{
          processed: Map.put(metrics.processed, r.worker_id, length(r.results)),
          steals: Map.put(metrics.steals, r.worker_id, r.steals),
          stolen: Map.put(metrics.stolen, r.worker_id, r.stolen)
        }
      end
    )
  end