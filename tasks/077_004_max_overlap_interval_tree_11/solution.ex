  @spec best_of(t()) :: integer()
  defp best_of(nil), do: @neg_inf
  defp best_of(%{best: b}), do: b