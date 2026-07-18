  # Fold the child's max_finish into a running maximum.
  @spec max_with_child(integer(), t()) :: integer()
  defp max_with_child(acc, nil), do: acc
  defp max_with_child(acc, %{max_finish: mf}), do: max(acc, mf)