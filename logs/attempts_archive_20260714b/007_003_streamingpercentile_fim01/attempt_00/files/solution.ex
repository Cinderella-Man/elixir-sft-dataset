  defp valid_quantile?(q) when is_number(q), do: q >= 0.0 and q <= 1.0
  defp valid_quantile?(_), do: false