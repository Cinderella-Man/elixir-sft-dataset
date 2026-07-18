  @doc """
  Returns the number of items currently stored in the buffer (0..capacity).

  ## Examples

      iex> RingBuffer.new(4) |> RingBuffer.size()
      0
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size