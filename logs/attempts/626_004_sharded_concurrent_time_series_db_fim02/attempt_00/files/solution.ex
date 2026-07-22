defp in_range_points(chunks, start_ts, end_ts) do
  chunks
  |> Map.values()
  |> Enum.concat()
  |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
  |> Enum.sort_by(fn {ts, _} -> ts end)
end