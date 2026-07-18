  defp orient(:left, record, counterpart), do: {record, counterpart}
  defp orient(:right, record, counterpart), do: {counterpart, record}