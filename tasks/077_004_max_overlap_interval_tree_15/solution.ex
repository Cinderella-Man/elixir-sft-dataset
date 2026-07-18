  @spec in_order(t(), [{integer(), integer()}]) :: [{integer(), integer()}]
  defp in_order(nil, acc), do: acc

  defp in_order(%{coord: c, delta: d, left: left, right: right}, acc) do
    in_order(left, [{c, d} | in_order(right, acc)])
  end