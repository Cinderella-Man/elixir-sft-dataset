# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RejectingRingBufferTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new buffer has size 0 and is not full" do
    buf = RejectingRingBuffer.new(4)
    assert RejectingRingBuffer.size(buf) == 0
    refute RejectingRingBuffer.full?(buf)
  end

  test "new buffer returns :error for peeks and :empty for pop" do
    buf = RejectingRingBuffer.new(4)
    assert :error = RejectingRingBuffer.peek_oldest(buf)
    assert :error = RejectingRingBuffer.peek_newest(buf)
    assert :empty = RejectingRingBuffer.pop(buf)
    assert [] = RejectingRingBuffer.to_list(buf)
  end

  # -------------------------------------------------------
  # Pushing below capacity
  # -------------------------------------------------------

  test "push returns {:ok, buffer} and grows size" do
    buf = RejectingRingBuffer.new(3)
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :a)
    assert RejectingRingBuffer.size(buf) == 1
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    assert RejectingRingBuffer.size(buf) == 2
    assert RejectingRingBuffer.to_list(buf) == [:a, :b]
  end

  test "peek_oldest and peek_newest reflect ends" do
    {:ok, buf} = RejectingRingBuffer.new(4) |> RejectingRingBuffer.push(:first)
    {:ok, buf} = RejectingRingBuffer.push(buf, :second)
    {:ok, buf} = RejectingRingBuffer.push(buf, :third)

    assert {:ok, :first} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, :third} = RejectingRingBuffer.peek_newest(buf)
  end

  # -------------------------------------------------------
  # Rejection when full
  # -------------------------------------------------------

  test "push is rejected with {:error, :full} at capacity" do
    {:ok, buf} = RejectingRingBuffer.new(2) |> RejectingRingBuffer.push(1)
    {:ok, buf} = RejectingRingBuffer.push(buf, 2)
    assert RejectingRingBuffer.full?(buf)
    assert {:error, :full} = RejectingRingBuffer.push(buf, 3)
  end

  test "rejected push leaves buffer contents unchanged" do
    {:ok, buf} = RejectingRingBuffer.new(2) |> RejectingRingBuffer.push(1)
    {:ok, full} = RejectingRingBuffer.push(buf, 2)

    assert {:error, :full} = RejectingRingBuffer.push(full, 99)
    # original 'full' buffer is untouched
    assert RejectingRingBuffer.to_list(full) == [1, 2]
    assert RejectingRingBuffer.size(full) == 2
  end

  # -------------------------------------------------------
  # FIFO pop semantics
  # -------------------------------------------------------

  test "pop removes items oldest-first" do
    {:ok, buf} = RejectingRingBuffer.new(3) |> RejectingRingBuffer.push(:a)
    {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    {:ok, buf} = RejectingRingBuffer.push(buf, :c)

    assert {:ok, :a, buf} = RejectingRingBuffer.pop(buf)
    assert {:ok, :b, buf} = RejectingRingBuffer.pop(buf)
    assert RejectingRingBuffer.to_list(buf) == [:c]
    assert {:ok, :c, buf} = RejectingRingBuffer.pop(buf)
    assert :empty = RejectingRingBuffer.pop(buf)
  end

  # -------------------------------------------------------
  # Wraparound via interleaved push/pop
  # -------------------------------------------------------

  test "freed slots are reused via wraparound" do
    buf = RejectingRingBuffer.new(3)
    {:ok, buf} = RejectingRingBuffer.push(buf, 1)
    {:ok, buf} = RejectingRingBuffer.push(buf, 2)
    {:ok, buf} = RejectingRingBuffer.push(buf, 3)
    assert {:error, :full} = RejectingRingBuffer.push(buf, 4)

    {:ok, 1, buf} = RejectingRingBuffer.pop(buf)
    # Now there is room again; the new slot wraps around the tuple
    {:ok, buf} = RejectingRingBuffer.push(buf, 4)
    assert RejectingRingBuffer.to_list(buf) == [2, 3, 4]

    {:ok, 2, buf} = RejectingRingBuffer.pop(buf)
    {:ok, buf} = RejectingRingBuffer.push(buf, 5)
    assert RejectingRingBuffer.to_list(buf) == [3, 4, 5]
    assert {:ok, 3} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, 5} = RejectingRingBuffer.peek_newest(buf)
  end

  test "many cycles preserve FIFO correctness" do
    buf = RejectingRingBuffer.new(4)

    final =
      Enum.reduce(1..20, buf, fn i, acc ->
        acc =
          case RejectingRingBuffer.push(acc, i) do
            {:ok, next} -> next
            {:error, :full} -> acc
          end

        # Drain one every other step to force wraparound
        if rem(i, 2) == 0 do
          case RejectingRingBuffer.pop(acc) do
            {:ok, _item, next} -> next
            :empty -> acc
          end
        else
          acc
        end
      end)

    assert RejectingRingBuffer.size(final) <= 4

    assert RejectingRingBuffer.to_list(final) |> Enum.sort() ==
             RejectingRingBuffer.to_list(final)
  end

  # -------------------------------------------------------
  # Capacity of 1
  # -------------------------------------------------------

  test "capacity-1 buffer accepts then rejects until popped" do
    buf = RejectingRingBuffer.new(1)
    {:ok, buf} = RejectingRingBuffer.push(buf, :only)
    assert {:error, :full} = RejectingRingBuffer.push(buf, :nope)
    {:ok, :only, buf} = RejectingRingBuffer.pop(buf)
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :again)
    assert RejectingRingBuffer.to_list(buf) == [:again]
  end

  # -------------------------------------------------------
  # Type variety
  # -------------------------------------------------------

  test "works with mixed value types" do
    buf = RejectingRingBuffer.new(5)
    {:ok, buf} = RejectingRingBuffer.push(buf, 42)
    {:ok, buf} = RejectingRingBuffer.push(buf, "hello")
    {:ok, buf} = RejectingRingBuffer.push(buf, :atom)
    {:ok, buf} = RejectingRingBuffer.push(buf, {:tuple, 1})
    {:ok, buf} = RejectingRingBuffer.push(buf, [1, 2, 3])

    assert RejectingRingBuffer.to_list(buf) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end

  test "full? is false one slot below capacity and flips true exactly at capacity" do
    buf = RejectingRingBuffer.new(3)
    {:ok, buf} = RejectingRingBuffer.push(buf, :a)
    refute RejectingRingBuffer.full?(buf)
    {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    assert RejectingRingBuffer.size(buf) == 2
    refute RejectingRingBuffer.full?(buf)
    {:ok, buf} = RejectingRingBuffer.push(buf, :c)
    assert RejectingRingBuffer.full?(buf)

    {:ok, :a, buf} = RejectingRingBuffer.pop(buf)
    refute RejectingRingBuffer.full?(buf)
  end

  test "peek_newest is correct when the write head has wrapped back to slot zero" do
    buf = RejectingRingBuffer.new(3)
    {:ok, buf} = RejectingRingBuffer.push(buf, :a)
    {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    {:ok, buf} = RejectingRingBuffer.push(buf, :c)

    # write head has just wrapped to 0; newest must still be the last push
    assert {:ok, :c} = RejectingRingBuffer.peek_newest(buf)
    assert {:ok, :a} = RejectingRingBuffer.peek_oldest(buf)

    {:ok, :a, buf} = RejectingRingBuffer.pop(buf)
    {:ok, buf} = RejectingRingBuffer.push(buf, :d)
    {:ok, :b, buf} = RejectingRingBuffer.pop(buf)
    {:ok, :c, buf} = RejectingRingBuffer.pop(buf)
    assert {:ok, :d} = RejectingRingBuffer.peek_newest(buf)
    assert {:ok, :d} = RejectingRingBuffer.peek_oldest(buf)
  end

  test "buffer drained after wraparound reports empty on every reader" do
    # TODO
  end

  test "nil and duplicate items are stored as real values in insertion order" do
    buf = RejectingRingBuffer.new(4)
    {:ok, buf} = RejectingRingBuffer.push(buf, nil)
    {:ok, buf} = RejectingRingBuffer.push(buf, :dup)
    {:ok, buf} = RejectingRingBuffer.push(buf, :dup)
    {:ok, buf} = RejectingRingBuffer.push(buf, nil)

    assert RejectingRingBuffer.size(buf) == 4
    assert RejectingRingBuffer.full?(buf)
    assert RejectingRingBuffer.to_list(buf) == [nil, :dup, :dup, nil]
    assert {:ok, nil} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, nil} = RejectingRingBuffer.peek_newest(buf)
    assert {:error, :full} = RejectingRingBuffer.push(buf, :extra)
    assert {:ok, nil, _} = RejectingRingBuffer.pop(buf)
  end

  test "repeated rejected pushes never change size or contents" do
    buf = RejectingRingBuffer.new(2)
    {:ok, buf} = RejectingRingBuffer.push(buf, :x)
    {:ok, buf} = RejectingRingBuffer.push(buf, :y)

    Enum.each(1..5, fn i ->
      assert {:error, :full} = RejectingRingBuffer.push(buf, i)
    end)

    assert RejectingRingBuffer.size(buf) == 2
    assert RejectingRingBuffer.to_list(buf) == [:x, :y]
    assert {:ok, :x} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, :y} = RejectingRingBuffer.peek_newest(buf)
  end

  test "slots are reused across several complete wraps of the backing store" do
    buf = RejectingRingBuffer.new(3)
    {:ok, buf} = RejectingRingBuffer.push(buf, 0)

    final =
      Enum.reduce(1..12, buf, fn i, acc ->
        {:ok, oldest} = RejectingRingBuffer.peek_oldest(acc)
        assert oldest == i - 1
        {:ok, next} = RejectingRingBuffer.push(acc, i)
        assert RejectingRingBuffer.to_list(next) == [i - 1, i]
        assert {:ok, ^i} = RejectingRingBuffer.peek_newest(next)
        {:ok, ^oldest, next} = RejectingRingBuffer.pop(next)
        next
      end)

    assert RejectingRingBuffer.to_list(final) == [12]
    assert RejectingRingBuffer.size(final) == 1
  end
end
```
