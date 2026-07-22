defmodule RingBuffer do
  @moduledoc """
  A fixed-size ring buffer implemented as a pure data structure.

  The buffer is backed by a tuple pre-allocated to `capacity` slots. Two integer
  head indices (`read` and `write`) walk the slots and wrap around using `rem/2`,
  so pushing never allocates a larger backing store and never shifts elements.

  When the buffer is full, `push/2` silently overwrites the oldest item and
  advances the read head, keeping the buffer at exactly `capacity` items.

      iex> buffer = RingBuffer.new(2)
      iex> buffer = RingBuffer.push(buffer, :a)
      iex> buffer = RingBuffer.push(buffer, :b)
      iex> buffer = RingBuffer.push(buffer, :c)
      iex> RingBuffer.to_list(buffer)
      [:b, :c]

  All functions are pure: they return a new buffer rather than mutating state.
  """

  @enforce_keys [:store, :capacity, :read, :size]
  defstruct [:store, :capacity, :read, :size]

  @typedoc "A ring buffer holding items of type `t:item/0`."
  @type t :: %__MODULE__{
          store: tuple(),
          capacity: pos_integer(),
          read: non_neg_integer(),
          size: non_neg_integer()
        }

  @typedoc "Any term may be stored in the buffer."
  @type item :: term()

  @doc """
  Creates a new empty ring buffer with a fixed `capacity`.

  The backing tuple is pre-allocated with `capacity` slots filled with `nil`.
  Raises `ArgumentError` unless `capacity` is a positive integer.

  ## Examples

      iex> buffer = RingBuffer.new(3)
      iex> RingBuffer.size(buffer)
      0
  """
  @spec new(pos_integer()) :: t()
  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      store: Tuple.duplicate(nil, capacity),
      capacity: capacity,
      read: 0,
      size: 0
    }
  end

  def new(capacity) do
    raise ArgumentError, "capacity must be a positive integer, got: #{inspect(capacity)}"
  end

  @doc """
  Inserts `item` at the write head, returning the updated buffer.

  When the buffer is full, the oldest item is silently overwritten and the read
  head advances, so the size stays pinned at `capacity`.

  ## Examples

      iex> buffer = RingBuffer.new(1) |> RingBuffer.push(:a) |> RingBuffer.push(:b)
      iex> RingBuffer.to_list(buffer)
      [:b]
  """
  @spec push(t(), item()) :: t()
  def push(%__MODULE__{} = buffer, item) do
    %__MODULE__{store: store, capacity: capacity, read: read, size: size} = buffer
    write = rem(read + size, capacity)
    store = put_elem(store, write, item)

    if size < capacity do
      %__MODULE__{buffer | store: store, size: size + 1}
    else
      %__MODULE__{buffer | store: store, read: rem(read + 1, capacity)}
    end
  end

  @doc """
  Returns every item currently stored, ordered from oldest to newest.

  ## Examples

      iex> buffer = RingBuffer.new(3) |> RingBuffer.push(:a) |> RingBuffer.push(:b)
      iex> RingBuffer.to_list(buffer)
      [:a, :b]

      iex> RingBuffer.to_list(RingBuffer.new(3))
      []
  """
  @spec to_list(t()) :: [item()]
  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{store: store, capacity: capacity, read: read, size: size}) do
    Enum.map(0..(size - 1), fn offset -> elem(store, rem(read + offset, capacity)) end)
  end

  @doc """
  Returns the number of items currently stored, which is at most the capacity.

  ## Examples

      iex> RingBuffer.new(5) |> RingBuffer.push(:a) |> RingBuffer.size()
      1
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Returns the capacity the buffer was created with.

  ## Examples

      iex> RingBuffer.capacity(RingBuffer.new(5))
      5
  """
  @spec capacity(t()) :: pos_integer()
  def capacity(%__MODULE__{capacity: capacity}), do: capacity

  @doc """
  Returns `{:ok, item}` for the oldest item, or `:error` when the buffer is empty.

  ## Examples

      iex> RingBuffer.new(2) |> RingBuffer.push(:a) |> RingBuffer.peek_oldest()
      {:ok, :a}

      iex> RingBuffer.peek_oldest(RingBuffer.new(2))
      :error
  """
  @spec peek_oldest(t()) :: {:ok, item()} | :error
  def peek_oldest(%__MODULE__{size: 0}), do: :error
  def peek_oldest(%__MODULE__{store: store, read: read}), do: {:ok, elem(store, read)}

  @doc """
  Returns `{:ok, item}` for the newest item, or `:error` when the buffer is empty.

  ## Examples

      iex> RingBuffer.new(2) |> RingBuffer.push(:a) |> RingBuffer.push(:b)
      ...> |> RingBuffer.peek_newest()
      {:ok, :b}

      iex> RingBuffer.peek_newest(RingBuffer.new(2))
      :error
  """
  @spec peek_newest(t()) :: {:ok, item()} | :error
  def peek_newest(%__MODULE__{size: 0}), do: :error

  def peek_newest(%__MODULE__{store: store, capacity: capacity, read: read, size: size}) do
    {:ok, elem(store, rem(read + size - 1, capacity))}
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(buffer, opts) do
      concat([
        "#RingBuffer<",
        to_doc(RingBuffer.to_list(buffer), opts),
        ", capacity: ",
        to_doc(RingBuffer.capacity(buffer), opts),
        ">"
      ])
    end
  end
end