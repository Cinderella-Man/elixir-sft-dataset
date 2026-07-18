  defp ensure_float_values(map) do
    Map.new(map, fn {k, v} -> {k, v / 1} end)
  end