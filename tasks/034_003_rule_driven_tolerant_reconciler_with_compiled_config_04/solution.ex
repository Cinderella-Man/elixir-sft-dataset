  defp equal?(:exact, left, right), do: left == right

  defp equal?({:numeric, tolerance}, left, right) when is_number(left) and is_number(right) do
    abs(left - right) <= tolerance
  end

  defp equal?(:case_insensitive, left, right) when is_binary(left) and is_binary(right) do
    normalize_string(left) == normalize_string(right)
  end

  defp equal?(_rule, left, right), do: left == right