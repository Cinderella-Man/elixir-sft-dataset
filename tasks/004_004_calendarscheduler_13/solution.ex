  defp bump_month(year, 12), do: {year + 1, 1}
  defp bump_month(year, month), do: {year, month + 1}