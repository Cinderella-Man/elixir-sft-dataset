  defp update_metric_stats(acc, name, value) do
    Map.update!(acc, :per_metric, fn metrics ->
      Map.update(metrics, name, %{count: 1, min: value, max: value, sum: value}, fn stats ->
        %{
          stats
          | count: stats.count + 1,
            min: min(stats.min, value),
            max: max(stats.max, value),
            sum: stats.sum + value
        }
      end)
    end)
  end