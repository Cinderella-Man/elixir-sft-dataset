defp apply_duration(datetime, []), do: datetime

defp apply_duration(datetime, [{unit, amount} | rest]) do
  canonical = Map.fetch!(@unit_aliases, unit)

  datetime
  |> DateTime.add(amount, canonical)
  |> apply_duration(rest)
end