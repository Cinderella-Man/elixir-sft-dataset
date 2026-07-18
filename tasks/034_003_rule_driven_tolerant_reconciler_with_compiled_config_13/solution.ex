  defp valid_rule?(:exact), do: true
  defp valid_rule?(:ignore), do: true
  defp valid_rule?(:case_insensitive), do: true
  defp valid_rule?({:numeric, tolerance}) when is_number(tolerance), do: tolerance >= 0
  defp valid_rule?(_rule), do: false