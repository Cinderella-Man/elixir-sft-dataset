  defp hour_bucket(%DateTime{year: y, month: m, day: d, hour: h}) do
    {{y, m, d}, h}
  end