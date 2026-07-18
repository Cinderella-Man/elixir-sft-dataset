  # Build a {date_tuple, hour} bucket key from a UTC DateTime.
  defp hour_bucket(%DateTime{year: y, month: m, day: d, hour: h}) do
    {{y, m, d}, h}
  end