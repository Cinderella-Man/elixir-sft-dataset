  defp max_month_day(2), do: 29
  defp max_month_day(month) when month in [4, 6, 9, 11], do: 30
  defp max_month_day(_month), do: 31