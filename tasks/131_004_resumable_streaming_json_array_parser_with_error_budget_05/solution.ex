  @spec exceeds?(non_neg_integer(), non_neg_integer() | :infinity) :: boolean()
  defp exceeds?(_errors, :infinity), do: false
  defp exceeds?(errors, max) when is_integer(max), do: errors > max