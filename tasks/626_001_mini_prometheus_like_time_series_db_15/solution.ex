  defp compute_agg([], _agg), do: nil
  defp compute_agg([_], :rate), do: nil

  defp compute_agg(points, :avg) do
    values = Enum.map(points, fn {_, v} -> v end)
    Enum.sum(values) / length(values)
  end

  defp compute_agg(points, :sum) do
    points |> Enum.map(fn {_, v} -> v end) |> Enum.sum()
  end

  defp compute_agg(points, :max) do
    points |> Enum.map(fn {_, v} -> v end) |> Enum.max()
  end

  defp compute_agg(points, :rate) do
    {first_ts, first_v} = List.first(points)
    {last_ts, last_v} = List.last(points)

    if last_ts == first_ts do
      nil
    else
      (last_v - first_v) / ((last_ts - first_ts) / 1000)
    end
  end