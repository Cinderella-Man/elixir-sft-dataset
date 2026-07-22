  defp segments_match?([p | ps], [t | ts]) do
    (p == "*" or p == t) and segments_match?(ps, ts)
  end

  defp segments_match?([], []), do: true
  defp segments_match?(_, _), do: false