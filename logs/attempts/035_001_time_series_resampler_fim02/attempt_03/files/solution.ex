  defp aggregate(points, :last) do
    {_ts, value} = List.last(points)
    value
  end

  defp aggregate([{_ts, value} | _rest], :first) do
    value
  end

  defp aggregate(points, :count) do
    length(points)
  end

  defp aggregate(points, :sum) do
    Enum.reduce(points, 0, fn {_ts, value}, acc -> acc + value end)
  end

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_ts, value}, {sum_acc, count_acc} ->
        {sum_acc + value, count_acc + 1}
      end)

    sum / count
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