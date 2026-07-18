  # Floor a timestamp to the nearest interval boundary.  `Integer.floor_div/2`
  # rounds towards negative infinity, unlike `div/2` which truncates towards
  # zero and would misplace negative timestamps.
  @spec floor_bucket(integer(), pos_integer()) :: integer()
  defp floor_bucket(ts, interval_ms) do
    Integer.floor_div(ts, interval_ms) * interval_ms
  end