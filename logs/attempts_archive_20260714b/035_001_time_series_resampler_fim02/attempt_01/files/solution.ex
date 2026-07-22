  defp aggregate(points, :last) do
    # Points are already sorted ascending; last element has the latest ts.
    points |> List.last() |> elem(1)
  end

  defp aggregate(points, :first) do
    points |> hd() |> elem(1)
  end

  defp aggregate(points, :count) do
    length(points)
  end

  defp aggregate(points, :sum) do
    Enum.reduce(points, 0, fn {_ts, v}, acc -> acc + v end)
  end

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_ts, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
  end

  defp aggregate(points, :max) do
    points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  end

  defp aggregate(points, :min) do
    points |> Enum.map(&elem(&1, 1)) |> Enum.min()
  end