  defp minute_bucket(%DateTime{year: y, month: mo, day: d, hour: h, minute: m}) do
    {{y, mo, d}, {h, m}}
  end