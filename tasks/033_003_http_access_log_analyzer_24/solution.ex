  defp compute_error_rate(%{total: 0}), do: 0.0

  defp compute_error_rate(%{error_count: errors, total: total}) do
    errors / total
  end