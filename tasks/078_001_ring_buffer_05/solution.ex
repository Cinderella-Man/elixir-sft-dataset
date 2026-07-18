  @doc """
  Creates a new empty ring buffer with the given fixed `capacity`.

  ## Examples

      iex> RingBuffer.new(4)
      %RingBuffer{capacity: 4, read: 0, write: 0, size: 0, ...}
  """
  @spec new(pos_integer()) :: t()
  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      read: 0,
      write: 0,
      size: 0
    }
  end