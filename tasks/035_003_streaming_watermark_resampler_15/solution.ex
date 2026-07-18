  defp bump(nil, ts), do: ts
  defp bump(current, ts), do: max(current, ts)