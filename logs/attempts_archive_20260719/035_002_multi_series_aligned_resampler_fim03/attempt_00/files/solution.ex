  defp aggregate(points, :last),  do: points |> List.last() |> elem(1)
  defp aggregate(points, :first), do: points |> hd() |> elem(1)
  defp aggregate(points, :count), do: length(points)
  defp aggregate(points, :sum),   do: Enum.reduce(points, 0, fn {_t, v}, acc -> acc + v end)
  defp aggregate(points, :max),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp aggregate(points, :min),   do: points |> Enum.map(&elem(&1, 1)) |> Enum.min()

  defp aggregate(points, :mean) do
    {sum, count} =
      Enum.reduce(points, {0, 0}, fn {_t, v}, {s, c} -> {s + v, c + 1} end)

    sum / count
  end