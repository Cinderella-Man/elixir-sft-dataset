  @spec apply_limit([map()], non_neg_integer() | nil) :: [map()]
  defp apply_limit(results, nil), do: results
  defp apply_limit(results, limit) when is_integer(limit), do: Enum.take(results, limit)