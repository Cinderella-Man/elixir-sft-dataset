  defp aggregate(points, :last) do
    {_ts, value} = List.last(points)
    value
  end

  defp aggregate(points, :first) do
    {_ts, value} = hd(points)
    value
  end

  defp aggregate(points, :count), do: length(points)

  defp aggregate(points, :sum) do
    Enum.reduce(points, 0, fn {_ts, value}, acc -> acc + value end)
  end

  defp aggregate(points, :max) do
    points
    |> Enum.map(fn {_ts, value} -> value end)
    |> Enum.max()
  end

  defp aggregate(points, :min) do
    points
    |> Enum.map(fn {_ts, value} -> value end)
    |> Enum.min()
  end

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_ts, value}, {s, c} -> {s + value, c + 1} end)

    sum / count
  end