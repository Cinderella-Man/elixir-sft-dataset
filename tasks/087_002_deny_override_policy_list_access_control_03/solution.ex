  defp field_match?(:any, _value), do: true
  defp field_match?(expected, value) when is_list(expected), do: value in expected
  defp field_match?(expected, value), do: expected == value