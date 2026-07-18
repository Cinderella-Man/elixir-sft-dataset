  @spec sum_of(t()) :: integer()
  defp sum_of(nil), do: 0
  defp sum_of(%{sum: s}), do: s