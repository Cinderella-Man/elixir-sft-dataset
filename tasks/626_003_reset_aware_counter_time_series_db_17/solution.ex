  @spec compute(function_kind(), [point()]) :: :omit | {:ok, number()}
  defp compute(:increase, points) when length(points) < 2, do: :omit
  defp compute(:increase, points), do: {:ok, reset_aware_increase(points)}

  defp compute(:rate, points) when length(points) < 2, do: :omit

  defp compute(:rate, points) do
    {first_ts, _v} = hd(points)
    {last_ts, _w} = List.last(points)

    if last_ts == first_ts do
      :omit
    else
      increase = reset_aware_increase(points)
      {:ok, increase / ((last_ts - first_ts) / 1000)}
    end
  end