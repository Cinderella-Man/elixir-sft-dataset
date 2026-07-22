  defp bucket_for(value) do
    boundaries = :persistent_term.get({@table, :buckets})
    Enum.find(boundaries, :inf, fn b -> value <= b end)
  end