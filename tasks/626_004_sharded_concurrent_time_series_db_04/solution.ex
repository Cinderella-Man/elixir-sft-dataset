  defp apply_agg(:sum, vals), do: Enum.sum(vals)
  defp apply_agg(:avg, vals), do: Enum.sum(vals) / length(vals)
  defp apply_agg(:max, vals), do: Enum.max(vals)