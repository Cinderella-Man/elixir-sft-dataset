# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

I need a pure-data-structure ring buffer from you — an Elixir module called `RejectingRingBuffer` that implements a fixed-size ring buffer as a plain struct with functions. No GenServer, please; I just want the data structure and its functions.

The twist versus a classic overwriting ring buffer: mine has to **reject** new items when it's full rather than silently discarding the oldest one. Think of it as a bounded FIFO queue — when it fills up, you `pop` items off the front to make room again.

Here's the public API I'm after:
- `RejectingRingBuffer.new(capacity)` — creates a new empty buffer with the given fixed capacity.
- `RejectingRingBuffer.push(buffer, item)` — attempts to insert an item at the back. It returns `{:ok, new_buffer}` on success, or `{:error, :full}` when the buffer is already at capacity, and in that failure case it does NOT mutate anything.
- `RejectingRingBuffer.pop(buffer)` — removes and returns the oldest item, giving back `{:ok, item, new_buffer}`, or `:empty` if the buffer holds no items.
- `RejectingRingBuffer.to_list(buffer)` — returns all current items in insertion order, oldest to newest; when the buffer is empty it returns `[]`.
- `RejectingRingBuffer.size(buffer)` — returns the number of items currently stored, from 0 up to capacity.
- `RejectingRingBuffer.full?(buffer)` — returns `true` when `size == capacity`, and `false` otherwise.
- `RejectingRingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `RejectingRingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if empty.

One thing I care about a lot: items may be any Elixir term, `nil` included. Store every pushed value verbatim — duplicates and `nil` are real stored entries, not empty slots — so `peek_oldest`/`peek_newest` on a stored `nil` must come back as `{:ok, nil}`, and emptiness must be decided purely by the `size`/`read`/`write` bookkeeping, never by a `nil` check.

On the internals, I want a fixed-size tuple pre-allocated to `capacity` slots as the backing store, with integer read/write head indices that wrap around using `rem/2`. Interleaving `push` and `pop` has to correctly reuse freed slots via that wraparound. Don't reach for a list or an `Enum`-grown structure as the primary store.

Send it back as the complete module in a single file, using only the Elixir standard library — no external dependencies.

## The buggy module

```elixir
defmodule RejectingRingBuffer do
  @moduledoc """
  A fixed-size ring buffer that behaves as a bounded FIFO queue.

  Unlike an overwriting ring buffer, `push/2` REJECTS new items with
  `{:error, :full}` once the buffer reaches `capacity`; it never discards
  live data. Callers make room by `pop/1`-ing the oldest item off the front.

  Internally, items live in a fixed-size tuple pre-allocated to `capacity`
  slots. Two integer indices — `write` (next slot to write) and `read`
  (oldest readable slot) — advance with `rem/2` so they wrap around the
  tuple automatically. Interleaving pushes and pops reuses freed slots.
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

  @doc "Creates a new empty buffer with the given fixed `capacity`."
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
  Attempts to insert `item` at the back.

  Returns `{:ok, buffer}` on success, or `{:error, :full}` when the buffer
  is already at capacity (in which case nothing is stored).
  """
  @spec push(t(), any()) :: {:ok, t()} | {:error, :full}
  def push(%__MODULE__{size: size, capacity: capacity}, _item) when size == capacity do
    {:error, :full}
  end

  def push(%__MODULE__{capacity: cap, store: store, write: write, size: size} = buf, item) do
    new_store = :erlang.setelement(write + 2, store, item)
    {:ok, %{buf | store: new_store, write: rem(write + 1, cap), size: size + 1}}
  end

  @doc """
  Removes and returns the oldest item.

  Returns `{:ok, item, buffer}`, or `:empty` when the buffer holds nothing.
  """
  @spec pop(t()) :: {:ok, any(), t()} | :empty
  def pop(%__MODULE__{size: 0}), do: :empty

  def pop(%__MODULE__{capacity: cap, store: store, read: read, size: size} = buf) do
    item = :erlang.element(read + 1, store)
    {:ok, item, %{buf | read: rem(read + 1, cap), size: size - 1}}
  end

  @doc "Returns all live items in insertion order (oldest → newest)."
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, read: read, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(read + offset, cap) + 1, store)
    end)
  end

  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns `true` when the buffer is at capacity."
  @spec full?(t()) :: boolean()
  def full?(%__MODULE__{size: size, capacity: capacity}), do: size == capacity

  @doc "Returns `{:ok, item}` for the oldest item, or `:error` if empty."
  @spec peek_oldest(t()) :: {:ok, any()} | :error
  def peek_oldest(%__MODULE__{size: 0}), do: :error

  def peek_oldest(%__MODULE__{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end

  @doc "Returns `{:ok, item}` for the newest item, or `:error` if empty."
  @spec peek_newest(t()) :: {:ok, any()} | :error
  def peek_newest(%__MODULE__{size: 0}), do: :error

  def peek_newest(%__MODULE__{capacity: cap, store: store, write: write}) do
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end
end
```

## Failing test report

```
9 of 11 test(s) failed:

  * test push returns {:ok, buffer} and grows size
      
      
      Assertion with == failed
      code:  assert RejectingRingBuffer.to_list(buf) == [:a, :b]
      left:  [nil, :a]
      right: [:a, :b]
      

  * test peek_oldest and peek_newest reflect ends
      
      
      match (=) failed
      code:  assert {:ok, :first} = RejectingRingBuffer.peek_oldest(buf)
      left:  {:ok, :first}
      right: {:ok, nil}
      

  * test push is rejected with {:error, :full} at capacity
      errors were found at the given arguments:
      
        * 1st argument: out of range
      

  * test rejected push leaves buffer contents unchanged
      errors were found at the given arguments:
      
        * 1st argument: out of range
      

  (…5 more)
```
