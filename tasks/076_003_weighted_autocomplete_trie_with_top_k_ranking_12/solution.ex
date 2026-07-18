  @doc "Returns the number of distinct words. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size