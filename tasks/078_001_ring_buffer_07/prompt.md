# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `peek_oldest`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design brief: `RingBuffer`

## Problem

We need a fixed-size ring buffer in Elixir — the kind of structure that holds the last N items and quietly discards older ones as new data arrives. It must be a pure data structure: no GenServer, no process, just a plain struct with functions operating on it.

## Constraints

- The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`.
- Do not use a list or a `Enum`-grown structure as the primary store.
- Only the Elixir standard library may be used — no external dependencies.
- The deliverable is the complete module in a single file.

## Required interface

The public API must consist of these functions:

1. `RingBuffer.new(capacity)` — creates a new empty ring buffer with the given fixed capacity.
2. `RingBuffer.push(buffer, item)` — inserts an item. When the buffer is full, it silently overwrites the oldest item.
3. `RingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest).
4. `RingBuffer.size(buffer)` — returns the number of items currently stored (not the capacity). This is 0 for an empty buffer and at most `capacity`.
5. `RingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if the buffer is empty.
6. `RingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if the buffer is empty.

## Acceptance criteria

- A module named `RingBuffer` exists and implements the fixed-size ring buffer as a plain struct with functions — not a GenServer.
- All six functions above are present in the public API and behave exactly as described, including the overwrite-oldest behavior on a full buffer, the oldest-to-newest ordering of `RingBuffer.to_list(buffer)`, the 0-to-`capacity` range of `RingBuffer.size(buffer)`, and the `{:ok, item}` / `:error` returns of the two peek functions.
- The backing store is a fixed-size tuple pre-allocated to `capacity` slots, indexed by integer read/write heads that wrap via `rem/2`; no list or `Enum`-grown structure serves as the primary store.
- Everything ships as one file, standard library only.

## The module with `peek_oldest` missing

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

  def peek_oldest(%__MODULE__{size: 0}) do
    # TODO
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

Output only `peek_oldest` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
