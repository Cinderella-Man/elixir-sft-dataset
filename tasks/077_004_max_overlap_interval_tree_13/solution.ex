  @spec balance_factor(t()) :: integer()
  defp balance_factor(nil), do: 0
  defp balance_factor(%{left: l, right: r}), do: height(l) - height(r)