  @doc "Total number of distinct items inserted."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count