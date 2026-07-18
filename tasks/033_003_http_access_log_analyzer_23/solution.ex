  defp compute_avg_duration(%{total: 0}), do: 0.0

  defp compute_avg_duration(%{duration_sum: sum, total: total}) do
    sum / total
  end