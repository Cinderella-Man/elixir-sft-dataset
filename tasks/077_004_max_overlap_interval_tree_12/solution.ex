  @spec height(t()) :: non_neg_integer()
  defp height(nil), do: 0
  defp height(%{height: h}), do: h