  defp insert_by_ts([], _ts, point), do: [point]

  defp insert_by_ts([{head_ts, _v} = head | rest], ts, point) when head_ts <= ts do
    [head | insert_by_ts(rest, ts, point)]
  end

  defp insert_by_ts(list, _ts, point), do: [point | list]