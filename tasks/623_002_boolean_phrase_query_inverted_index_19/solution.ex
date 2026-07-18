  defp intersect_all([]), do: MapSet.new()

  defp intersect_all([first | rest]) do
    Enum.reduce(rest, first, fn set, acc -> MapSet.intersection(acc, set) end)
  end