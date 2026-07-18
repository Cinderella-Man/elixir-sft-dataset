  defp parse_range_or_star("*", lo, hi) do
    {:ok, MapSet.new(lo..hi)}
  end

  defp parse_range_or_star(other, lo, hi) do
    parse_range_or_value(other, lo, hi)
  end