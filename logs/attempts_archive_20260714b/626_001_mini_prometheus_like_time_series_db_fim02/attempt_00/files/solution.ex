  defp aggregate(points, start_ts, end_ts, aggregation, step_ms) do
    windows = build_windows(start_ts, end_ts, step_ms)

    Enum.flat_map(windows, fn window_start ->
      window_end = window_start + step_ms

      window_points =
        Enum.filter(points, fn {ts, _} ->
          ts >= window_start and ts < window_end
        end)

      case compute_agg(window_points, aggregation) do
        nil -> []
        agg_value -> [{window_start, agg_value}]
      end
    end)
  end