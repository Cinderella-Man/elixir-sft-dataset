  @doc """
  Returns the maximum number of intervals covering any single integer point.

  Returns `0` for an empty tree.
  """
  @spec max_overlap(t()) :: non_neg_integer()
  def max_overlap(nil), do: 0
  def max_overlap(%{best: best}), do: max(0, best)