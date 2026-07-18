# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `pop` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `RejectingRingBuffer` that implements a fixed-size ring buffer as a pure data structure (no GenServer — just a plain struct with functions).

Unlike a classic overwriting ring buffer, this one **rejects** new items when it is full instead of silently discarding the oldest. It behaves as a bounded FIFO queue: you can `pop` items off the front to make room again.

I need these functions in the public API:
- `RejectingRingBuffer.new(capacity)` — creates a new empty buffer with the given fixed capacity.
- `RejectingRingBuffer.push(buffer, item)` — attempts to insert an item at the back. Returns `{:ok, new_buffer}` on success, or `{:error, :full}` (and does NOT mutate) when the buffer is already at capacity.
- `RejectingRingBuffer.pop(buffer)` — removes and returns the oldest item. Returns `{:ok, item, new_buffer}`, or `:empty` if the buffer holds no items.
- `RejectingRingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest); returns `[]` when empty.
- `RejectingRingBuffer.size(buffer)` — returns the number of items currently stored (0 to capacity).
- `RejectingRingBuffer.full?(buffer)` — returns `true` when `size == capacity`, else `false`.
- `RejectingRingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `RejectingRingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if empty.

Items may be any Elixir term, including `nil`. Store every pushed value verbatim: duplicates and `nil` are real stored entries (not empty slots), so `peek_oldest`/`peek_newest` on a stored `nil` must return `{:ok, nil}`, and only `size`/`read`/`write` bookkeeping — never a `nil` check — determines emptiness.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`. Interleaving `push` and `pop` must correctly reuse freed slots via wraparound. Do not use a list or an `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.

## The module with `pop` missing

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
    new_store = :erlang.setelement(write + 1, store, item)
    {:ok, %{buf | store: new_store, write: rem(write + 1, cap), size: size + 1}}
  end

  def pop(%__MODULE__{size: 0}) do
    # TODO
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

Give me only the complete implementation of `pop` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
