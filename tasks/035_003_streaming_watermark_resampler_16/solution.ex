  # Integer.floor_div/2 rounds toward negative infinity, so negative timestamps
  # land in the bucket below them (e.g. -500 with a 1000ms grid -> -1000).
  defp floor_bucket(ts, interval), do: Integer.floor_div(ts, interval) * interval