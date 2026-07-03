  defp compute_wma([], _period), do: 0.0

  defp compute_wma(values, period) do
    window = Enum.take(values, period)
    n = length(window)

    # window is newest-first, so weight decreases as we move toward the tail
    {weighted_sum, weight_sum} =
      window
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0}, fn {v, i}, {ws, wt} ->
        weight = n - i
        {ws + v * weight, wt + weight}
      end)

    weighted_sum / weight_sum
  end