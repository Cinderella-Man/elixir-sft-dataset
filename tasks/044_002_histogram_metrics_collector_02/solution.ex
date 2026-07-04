def get(name) do
  case :ets.lookup(@table, {name, :count}) do
    [] ->
      nil

    [{_, count}] ->
      sum = counter({name, :sum})
      boundaries = :persistent_term.get({@table, :buckets})

      {cumulative, _running} =
        Enum.reduce(boundaries, {%{}, 0}, fn b, {acc, running} ->
          running = running + counter({name, :bucket, b})
          {Map.put(acc, b, running), running}
        end)

      buckets = Map.put(cumulative, :infinity, count)
      %{count: count, sum: sum, average: sum / count, buckets: buckets}
  end
end