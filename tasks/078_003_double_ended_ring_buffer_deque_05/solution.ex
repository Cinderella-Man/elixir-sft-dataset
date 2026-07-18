  @doc "Creates a new empty deque with the given fixed `capacity`."
  @spec new(pos_integer()) :: t()
  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      head: 0,
      size: 0
    }
  end