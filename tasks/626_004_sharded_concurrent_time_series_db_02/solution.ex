  defp aggregate(chunks, start_ts, end_ts, step, agg) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts < end_ts end)
    |> Enum.group_by(
      fn {ts, _} -> start_ts + div(ts - start_ts, step) * step end,
      fn {_, v} -> v end
    )
    |> Enum.map(fn {window_start, vals} -> {window_start, apply_agg(agg, vals)} end)
    |> Enum.sort_by(fn {window_start, _} -> window_start end)
  end