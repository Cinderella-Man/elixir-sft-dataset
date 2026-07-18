  # Floored division, not truncation: a negative timestamp must land in the
  # bucket at or below it (floor(t / interval) * interval), matching the grid
  # rule for the earliest timestamp.
  defp floor_bucket(ts, interval_ms), do: Integer.floor_div(ts, interval_ms) * interval_ms