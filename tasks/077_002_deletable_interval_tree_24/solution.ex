  defp min_interval(%{left: nil, interval: iv}), do: iv
  defp min_interval(%{left: l}), do: min_interval(l)