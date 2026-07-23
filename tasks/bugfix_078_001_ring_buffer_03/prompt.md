# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir module called `RingBuffer` that implements a fixed-size ring buffer as a pure data structure (no GenServer — just a plain struct with functions).

I need these functions in the public API:
- `RingBuffer.new(capacity)` — creates a new empty ring buffer with the given fixed capacity.
- `RingBuffer.push(buffer, item)` — inserts an item. When the buffer is full, it silently overwrites the oldest item.
- `RingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest).
- `RingBuffer.size(buffer)` — returns the number of items currently stored (not the capacity). This is 0 for an empty buffer and at most `capacity`.
- `RingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if the buffer is empty.
- `RingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if the buffer is empty.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`. Do not use a list or a `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.

## The buggy module

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
    {:error, :erlang.element(newest_index + 1, store)}
  end
end
```

## Failing test report

```
3 of 17 test(s) failed:

  * test peek_newest returns the last item pushed
      
      
      match (=) failed
      code:  assert {:ok, :third} = RingBuffer.peek_newest(buf)
      left:  {:ok, :third}
      right: {:error, :third}
      

  * test peek_newest reflects the latest push after overwrites
      
      
      match (=) failed
      code:  assert {:ok, 40} = RingBuffer.peek_newest(buf)
      left:  {:ok, 40}
      right: {:error, 40}
      

  * test capacity-1 buffer always holds exactly one item
      
      
      match (=) failed
      code:  assert {:ok, :only} = RingBuffer.peek_newest(buf)
      left:  {:ok, :only}
      right: {:error, :only}
```
