# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule RingBuffer do
  @moduledoc """
  A fixed-size ring buffer implemented as a pure data structure.

  Internally, items are stored in a fixed-size tuple pre-allocated to
  `capacity` slots. Two integer indices — `write` (next slot to write)
  and `read` (oldest readable slot) — advance with `rem/2` so they wrap
  around automatically. `size` tracks the live item count independently,
  capping at `capacity`.

  When the buffer is full, `push/2` silently advances the read head
  alongside the write head, effectively discarding the oldest item.
  """

  @enforce_keys [:capacity, :store, :read, :write, :size]
  defstruct [:capacity, :store, :read, :write, :size]

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          store: tuple(),
          read: non_neg_integer(),
          write: non_neg_integer(),
          size: non_neg_integer()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  @doc """
  Inserts `item` into the buffer.

  If the buffer is full, the oldest item is silently overwritten and the
  read head advances so `size` stays equal to `capacity`.

  ## Examples

      iex> buf = RingBuffer.new(3) |> RingBuffer.push(1) |> RingBuffer.push(2)
      iex> RingBuffer.size(buf)
      2
  """
  @spec push(t(), any()) :: t()
  def push(%__MODULE__{} = buf, item) do
    %{capacity: cap, store: store, read: read, write: write, size: size} = buf

    # Write the item into the current write slot.
    new_store = :erlang.setelement(write + 1, store, item)
    new_write = rem(write + 1, cap)

    # If the buffer was already full, the write head just trampled the oldest
    # slot, so we must advance the read head to keep it pointing at the new
    # oldest item.  size stays at `cap`.
    if size == cap do
      %{buf | store: new_store, write: new_write, read: rem(read + 1, cap)}
    else
      %{buf | store: new_store, write: new_write, size: size + 1}
    end
  end

  @doc """
  Returns all live items in insertion order (oldest → newest).

  ## Examples

      iex> RingBuffer.new(4) |> RingBuffer.push(1) |> RingBuffer.push(2) |> RingBuffer.to_list()
      [1, 2]
  """
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, read: read, size: size}) do
    # Walk `size` slots starting from the read head, wrapping as needed.
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(read + offset, cap) + 1, store)
    end)
  end

  @doc """
  Returns the number of items currently stored in the buffer (0..capacity).

  ## Examples

      iex> RingBuffer.new(4) |> RingBuffer.size()
      0
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Returns `{:ok, item}` for the oldest (first-inserted) live item,
  or `:error` if the buffer is empty.

  ## Examples

      iex> RingBuffer.new(3) |> RingBuffer.push(:a)
      ...> |> RingBuffer.push(:b) |> RingBuffer.peek_oldest()
      {:ok, :a}

      iex> RingBuffer.new(3) |> RingBuffer.peek_oldest()
      :error
  """
  @spec peek_oldest(t()) :: {:ok, any()} | :error
  def peek_oldest(%__MODULE__{size: 0}), do: :error

  def peek_oldest(%__MODULE__{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end

  @doc """
  Returns `{:ok, item}` for the most recently pushed item,
  or `:error` if the buffer is empty.

  ## Examples

      iex> RingBuffer.new(3) |> RingBuffer.push(:a)
      ...> |> RingBuffer.push(:b) |> RingBuffer.peek_newest()
      {:ok, :b}

      iex> RingBuffer.new(3) |> RingBuffer.peek_newest()
      :error
  """
  @spec peek_newest(t()) :: {:ok, any()} | :error
  def peek_newest(%__MODULE__{size: 0}), do: :error

  def peek_newest(%__MODULE__{capacity: cap, store: store, write: write}) do
    # `write` points to the *next* slot to be written, so the newest item
    # sits one position behind it (with wraparound).
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end
end
```

## New specification

Write me an Elixir module called `RingDeque` that implements a fixed-size, double-ended ring buffer (a bounded deque) as a pure data structure (no GenServer — just a plain struct with functions).

Items can be pushed onto either end. When the deque is full, pushing to one end silently overwrites the element at the OPPOSITE end (push to the back drops the front; push to the front drops the back).

I need these functions in the public API:
- `RingDeque.new(capacity)` — creates a new empty deque with the given fixed capacity.
- `RingDeque.push_back(deque, item)` — appends at the back. When full, overwrites (drops) the current front.
- `RingDeque.push_front(deque, item)` — prepends at the front. When full, overwrites (drops) the current back.
- `RingDeque.pop_front(deque)` — removes and returns the front item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.pop_back(deque)` — removes and returns the back item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.to_list(deque)` — returns all current items in order from front to back.
- `RingDeque.size(deque)` — returns the number of items currently stored (0 to capacity).
- `RingDeque.peek_front(deque)` — returns `{:ok, item}` for the front item, or `:error` if empty.
- `RingDeque.peek_back(deque)` — returns `{:ok, item}` for the back item, or `:error` if empty.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with an integer head index and a live-count, both advancing with `rem/2` so all four operations wrap around the tuple in O(1). Do not use a list or an `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
