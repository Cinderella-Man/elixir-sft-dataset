  # Numeric comparison that returns false for non-numeric operands (including nil).
  defp num_cmp(a, b, op) when is_number(a) and is_number(b), do: op.(a, b)
  defp num_cmp(_, _, _), do: false