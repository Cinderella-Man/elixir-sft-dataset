  @doc "Returns the current number of live items."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{size: size}), do: size