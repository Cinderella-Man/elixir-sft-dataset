  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size