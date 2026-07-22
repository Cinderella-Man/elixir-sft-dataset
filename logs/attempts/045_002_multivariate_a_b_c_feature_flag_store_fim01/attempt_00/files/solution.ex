  defp select([{name, weight} | rest], bucket, acc) do
    upper = acc + weight
    if bucket < upper, do: name, else: select(rest, bucket, upper)
  end

  defp select([], _bucket, _acc), do: :off