defp segments_match?([], []), do: true
defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
defp segments_match?(_, _), do: false
