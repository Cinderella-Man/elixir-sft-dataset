# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

## Module under test

```elixir
defmodule RingDeque do
  @moduledoc """
  A fixed-size, double-ended ring buffer (bounded deque) as a pure data
  structure.

  Items may be pushed/popped at either end in O(1). When the deque is full,
  pushing to one end silently overwrites (drops) the element at the OPPOSITE
  end: `push_back/2` drops the front, `push_front/2` drops the back.

  Internally, items live in a fixed-size tuple pre-allocated to `capacity`
  slots. A single integer `head` marks the front position and `size` tracks
  the live count. The back slot is always `rem(head + size - 1, capacity)`
  and the next back write goes to `rem(head + size, capacity)`; `head` moves
  backwards (with wraparound) for front pushes. All indices advance with
  `rem/2`, so every operation wraps around the tuple automatically.
  """

  @enforce_keys [:capacity, :store, :head, :size]
  defstruct [:capacity, :store, :head, :size]

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          store: tuple(),
          head: non_neg_integer(),
          size: non_neg_integer()
        }

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

  @doc """
  Appends `item` at the back.

  When full, the current front is overwritten (dropped) so `size` stays at
  `capacity`.
  """
  @spec push_back(t(), any()) :: t()
  def push_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d, item) do
    slot = rem(head + size, cap)
    new_store = :erlang.setelement(slot + 1, store, item)

    if size == cap do
      # Full: the write landed on the old front slot; advance head to drop it.
      %{d | store: new_store, head: rem(head + 1, cap)}
    else
      %{d | store: new_store, size: size + 1}
    end
  end

  @doc """
  Prepends `item` at the front.

  When full, the current back is overwritten (dropped) so `size` stays at
  `capacity`.
  """
  @spec push_front(t(), any()) :: t()
  def push_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d, item) do
    new_head = rem(head - 1 + cap, cap)
    new_store = :erlang.setelement(new_head + 1, store, item)

    if size == cap do
      # Full: new_head coincides with the old back slot, dropping it.
      %{d | store: new_store, head: new_head}
    else
      %{d | store: new_store, head: new_head, size: size + 1}
    end
  end

  @doc "Removes and returns the front item, or `:empty`."
  @spec pop_front(t()) :: {:ok, any(), t()} | :empty
  def pop_front(%__MODULE__{size: 0}), do: :empty

  def pop_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    item = :erlang.element(head + 1, store)
    {:ok, item, %{d | head: rem(head + 1, cap), size: size - 1}}
  end

  @doc "Removes and returns the back item, or `:empty`."
  @spec pop_back(t()) :: {:ok, any(), t()} | :empty
  def pop_back(%__MODULE__{size: 0}), do: :empty

  def pop_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    slot = rem(head + size - 1, cap)
    item = :erlang.element(slot + 1, store)
    {:ok, item, %{d | size: size - 1}}
  end

  @doc "Returns all live items from front to back."
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(head + offset, cap) + 1, store)
    end)
  end

  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns `{:ok, item}` for the front item, or `:error` if empty."
  @spec peek_front(t()) :: {:ok, any()} | :error
  def peek_front(%__MODULE__{size: 0}), do: :error

  def peek_front(%__MODULE__{store: store, head: head}) do
    {:ok, :erlang.element(head + 1, store)}
  end

  @doc "Returns `{:ok, item}` for the back item, or `:error` if empty."
  @spec peek_back(t()) :: {:ok, any()} | :error
  def peek_back(%__MODULE__{size: 0}), do: :error

  def peek_back(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    slot = rem(head + size - 1, cap)
    {:ok, :erlang.element(slot + 1, store)}
  end
end
```
