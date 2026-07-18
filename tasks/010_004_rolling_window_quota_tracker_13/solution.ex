  @spec sum_usage([usage_entry()]) :: non_neg_integer()
  defp sum_usage(entries) do
    Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount end)
  end