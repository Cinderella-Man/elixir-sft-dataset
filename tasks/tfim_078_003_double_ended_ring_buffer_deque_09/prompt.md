# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RingDequeTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new deque is empty" do
    d = RingDeque.new(4)
    assert RingDeque.size(d) == 0
    assert RingDeque.to_list(d) == []
    assert :error = RingDeque.peek_front(d)
    assert :error = RingDeque.peek_back(d)
    assert :empty = RingDeque.pop_front(d)
    assert :empty = RingDeque.pop_back(d)
  end

  # -------------------------------------------------------
  # Basic push_back / push_front ordering
  # -------------------------------------------------------

  test "push_back appends to the back" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    assert RingDeque.to_list(d) == [1, 2, 3]
    assert {:ok, 1} = RingDeque.peek_front(d)
    assert {:ok, 3} = RingDeque.peek_back(d)
  end

  test "push_front prepends to the front" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_front(1)
      |> RingDeque.push_front(2)
      |> RingDeque.push_front(3)

    assert RingDeque.to_list(d) == [3, 2, 1]
    assert {:ok, 3} = RingDeque.peek_front(d)
    assert {:ok, 1} = RingDeque.peek_back(d)
  end

  test "mixed front/back pushes interleave correctly" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(:b)
      |> RingDeque.push_front(:a)
      |> RingDeque.push_back(:c)
      |> RingDeque.push_front(:z)

    assert RingDeque.to_list(d) == [:z, :a, :b, :c]
  end

  # -------------------------------------------------------
  # Popping from both ends
  # -------------------------------------------------------

  test "pop_front and pop_back remove the right ends" do
    d =
      RingDeque.new(4)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)
      |> RingDeque.push_back(4)

    assert {:ok, 1, d} = RingDeque.pop_front(d)
    assert {:ok, 4, d} = RingDeque.pop_back(d)
    assert RingDeque.to_list(d) == [2, 3]
    assert {:ok, 3, d} = RingDeque.pop_back(d)
    assert {:ok, 2, d} = RingDeque.pop_front(d)
    assert RingDeque.size(d) == 0
  end

  # -------------------------------------------------------
  # Overwrite semantics: push_back drops front
  # -------------------------------------------------------

  test "push_back at capacity overwrites the front" do
    d =
      RingDeque.new(3)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    assert RingDeque.to_list(d) == [1, 2, 3]

    d = RingDeque.push_back(d, 4)
    assert RingDeque.size(d) == 3
    assert RingDeque.to_list(d) == [2, 3, 4]

    d = RingDeque.push_back(d, 5)
    assert RingDeque.to_list(d) == [3, 4, 5]
    assert {:ok, 3} = RingDeque.peek_front(d)
    assert {:ok, 5} = RingDeque.peek_back(d)
  end

  # -------------------------------------------------------
  # Overwrite semantics: push_front drops back
  # -------------------------------------------------------

  test "push_front at capacity overwrites the back" do
    d =
      RingDeque.new(3)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    d = RingDeque.push_front(d, 0)
    assert RingDeque.size(d) == 3
    assert RingDeque.to_list(d) == [0, 1, 2]

    d = RingDeque.push_front(d, -1)
    assert RingDeque.to_list(d) == [-1, 0, 1]
    assert {:ok, -1} = RingDeque.peek_front(d)
    assert {:ok, 1} = RingDeque.peek_back(d)
  end

  # -------------------------------------------------------
  # Wraparound through the tuple
  # -------------------------------------------------------

  test "operations wrap around the backing tuple" do
    # TODO
  end

  # -------------------------------------------------------
  # Capacity of 1
  # -------------------------------------------------------

  test "capacity-1 deque holds exactly one item from either end" do
    d = RingDeque.new(1)
    d = RingDeque.push_back(d, :a)
    assert RingDeque.to_list(d) == [:a]

    d = RingDeque.push_back(d, :b)
    assert RingDeque.to_list(d) == [:b]

    d = RingDeque.push_front(d, :c)
    assert RingDeque.to_list(d) == [:c]
    assert {:ok, :c} = RingDeque.peek_front(d)
    assert {:ok, :c} = RingDeque.peek_back(d)
  end

  # -------------------------------------------------------
  # Type variety
  # -------------------------------------------------------

  test "works with mixed value types" do
    d =
      RingDeque.new(5)
      |> RingDeque.push_back(42)
      |> RingDeque.push_back("hello")
      |> RingDeque.push_front(:atom)
      |> RingDeque.push_back({:tuple, 1})
      |> RingDeque.push_front([1, 2, 3])

    assert RingDeque.to_list(d) == [[1, 2, 3], :atom, 42, "hello", {:tuple, 1}]
  end

  # -------------------------------------------------------
  # Backing representation: fixed-size tuple, not a list
  # -------------------------------------------------------

  test "new/1 pre-allocates a capacity-slot tuple as the store" do
    d = RingDeque.new(4)
    store = backing_tuple(d, 4)
    assert tuple_size(store) == 4

    # A head index and a live count are carried alongside the store.
    integers = d |> Map.from_struct() |> Map.values() |> Enum.filter(&is_integer/1)
    assert length(integers) >= 2
  end

  test "the store tuple holds the live items and keeps its capacity size" do
    d =
      RingDeque.new(3)
      |> RingDeque.push_back(:a)
      |> RingDeque.push_back(:b)
      |> RingDeque.push_back(:c)

    slots = d |> backing_tuple(3) |> Tuple.to_list()
    assert Enum.sort(slots) == Enum.sort(RingDeque.to_list(d))

    d =
      d
      |> RingDeque.push_back(:d)
      |> RingDeque.push_front(:z)
      |> RingDeque.push_back(:e)

    assert RingDeque.size(d) == 3
    slots = d |> backing_tuple(3) |> Tuple.to_list()
    assert Enum.sort(slots) == Enum.sort(RingDeque.to_list(d))

    {:ok, _, d} = RingDeque.pop_front(d)
    {:ok, _, d} = RingDeque.pop_back(d)
    d = RingDeque.push_front(d, :w)

    store = backing_tuple(d, 3)
    assert tuple_size(store) == 3
    assert Enum.all?(RingDeque.to_list(d), &(&1 in Tuple.to_list(store)))
  end

  # Returns the struct's single tuple field sized to `capacity`, failing if the
  # deque is backed by a list or by anything other than that fixed-size tuple.
  defp backing_tuple(deque, capacity) do
    fields = deque |> Map.from_struct() |> Map.values()

    refute Enum.any?(fields, &is_list/1),
           "the primary store must be a fixed-size tuple, not a list"

    assert [store] = Enum.filter(fields, &(is_tuple(&1) and tuple_size(&1) == capacity))
    store
  end
end
```
