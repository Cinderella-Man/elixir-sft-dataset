  @doc "Returns `true` when the buffer is at capacity."
  @spec full?(t()) :: boolean()
  def full?(%__MODULE__{size: size, capacity: capacity}), do: size == capacity