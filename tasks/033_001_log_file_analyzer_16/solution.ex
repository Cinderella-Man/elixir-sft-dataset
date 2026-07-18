  defp compute_error_rate(%{total: 0}), do: 0.0

  defp compute_error_rate(%{counts_by_level: counts, total: total}) do
    error_count = Map.get(counts, "error", 0)
    error_count / total
  end