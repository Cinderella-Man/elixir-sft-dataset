# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule RingBufferTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new buffer has size 0" do
    buf = RingBuffer.new(4)
    assert RingBuffer.size(buf) == 0
  end

  test "new buffer returns :error for peek_oldest" do
    buf = RingBuffer.new(4)
    assert :error = RingBuffer.peek_oldest(buf)
  end

  test "new buffer returns :error for peek_newest" do
    buf = RingBuffer.new(4)
    assert :error = RingBuffer.peek_newest(buf)
  end

  test "new buffer returns empty list" do
    buf = RingBuffer.new(4)
    assert [] = RingBuffer.to_list(buf)
  end

  # -------------------------------------------------------
  # Filling below capacity
  # -------------------------------------------------------

  test "size grows with each push up to capacity" do
    # TODO
  end

  test "to_list returns items in insertion order when under capacity" do
    buf =
      RingBuffer.new(5)
      |> RingBuffer.push(1)
      |> RingBuffer.push(2)
      |> RingBuffer.push(3)

    assert RingBuffer.to_list(buf) == [1, 2, 3]
  end

  test "peek_oldest returns the first item pushed" do
    buf =
      RingBuffer.new(4)
      |> RingBuffer.push(:first)
      |> RingBuffer.push(:second)
      |> RingBuffer.push(:third)

    assert {:ok, :first} = RingBuffer.peek_oldest(buf)
  end

  test "peek_newest returns the last item pushed" do
    buf =
      RingBuffer.new(4)
      |> RingBuffer.push(:first)
      |> RingBuffer.push(:second)
      |> RingBuffer.push(:third)

    assert {:ok, :third} = RingBuffer.peek_newest(buf)
  end

  # -------------------------------------------------------
  # Exact capacity
  # -------------------------------------------------------

  test "size does not exceed capacity" do
    buf = RingBuffer.new(3)
    buf = buf |> RingBuffer.push(:a) |> RingBuffer.push(:b) |> RingBuffer.push(:c)
    assert RingBuffer.size(buf) == 3

    # Push one more — size must stay at 3
    buf = RingBuffer.push(buf, :d)
    assert RingBuffer.size(buf) == 3
  end

  test "to_list at exactly full capacity returns all items" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)

    assert RingBuffer.to_list(buf) == [:a, :b, :c]
  end

  # -------------------------------------------------------
  # Overwrite behaviour (over capacity)
  # -------------------------------------------------------

  test "oldest item is overwritten when buffer is full" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(1)
      |> RingBuffer.push(2)
      |> RingBuffer.push(3)
      |> RingBuffer.push(4)

    # 1 should be gone; list should be oldest-first
    assert RingBuffer.to_list(buf) == [2, 3, 4]
  end

  test "multiple overwrites maintain correct insertion order" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)
      |> RingBuffer.push(:d)
      |> RingBuffer.push(:e)

    assert RingBuffer.to_list(buf) == [:c, :d, :e]
  end

  test "peek_oldest reflects the new oldest after overwrites" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(10)
      |> RingBuffer.push(20)
      |> RingBuffer.push(30)
      |> RingBuffer.push(40)

    assert {:ok, 20} = RingBuffer.peek_oldest(buf)
  end

  test "peek_newest reflects the latest push after overwrites" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(10)
      |> RingBuffer.push(20)
      |> RingBuffer.push(30)
      |> RingBuffer.push(40)

    assert {:ok, 40} = RingBuffer.peek_newest(buf)
  end

  test "many overwrites — only last capacity items survive" do
    capacity = 4

    buf =
      Enum.reduce(1..20, RingBuffer.new(capacity), fn i, b ->
        RingBuffer.push(b, i)
      end)

    assert RingBuffer.size(buf) == capacity
    assert RingBuffer.to_list(buf) == [17, 18, 19, 20]
  end

  # -------------------------------------------------------
  # Capacity of 1
  # -------------------------------------------------------

  test "capacity-1 buffer always holds exactly one item" do
    buf = RingBuffer.new(1)
    assert RingBuffer.size(buf) == 0

    buf = RingBuffer.push(buf, :only)
    assert RingBuffer.size(buf) == 1
    assert {:ok, :only} = RingBuffer.peek_oldest(buf)
    assert {:ok, :only} = RingBuffer.peek_newest(buf)

    buf = RingBuffer.push(buf, :replaced)
    assert RingBuffer.size(buf) == 1
    assert RingBuffer.to_list(buf) == [:replaced]
    assert {:ok, :replaced} = RingBuffer.peek_oldest(buf)
    assert {:ok, :replaced} = RingBuffer.peek_newest(buf)
  end

  # -------------------------------------------------------
  # Type variety
  # -------------------------------------------------------

  test "works with mixed value types" do
    buf =
      RingBuffer.new(5)
      |> RingBuffer.push(42)
      |> RingBuffer.push("hello")
      |> RingBuffer.push(:atom)
      |> RingBuffer.push({:tuple, 1})
      |> RingBuffer.push([1, 2, 3])

    assert RingBuffer.to_list(buf) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end

  test "peek_newest is correct when the write head wraps to slot zero" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)

    # Exactly full: the write head has wrapped back to slot 0.
    assert {:ok, :c} = RingBuffer.peek_newest(buf)
    assert {:ok, :a} = RingBuffer.peek_oldest(buf)
    assert RingBuffer.to_list(buf) == [:a, :b, :c]

    # One complete extra cycle: read and write heads coincide again while full.
    buf =
      buf
      |> RingBuffer.push(:d)
      |> RingBuffer.push(:e)
      |> RingBuffer.push(:f)

    assert RingBuffer.size(buf) == 3
    assert {:ok, :f} = RingBuffer.peek_newest(buf)
    assert {:ok, :d} = RingBuffer.peek_oldest(buf)
    assert RingBuffer.to_list(buf) == [:d, :e, :f]
  end

  test "push leaves the source buffer untouched and branches independently" do
    base =
      RingBuffer.new(2)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)

    left = RingBuffer.push(base, :left)
    right = RingBuffer.push(base, :right)

    assert RingBuffer.to_list(base) == [:a, :b]
    assert RingBuffer.size(base) == 2
    assert {:ok, :a} = RingBuffer.peek_oldest(base)
    assert {:ok, :b} = RingBuffer.peek_newest(base)

    assert RingBuffer.to_list(left) == [:b, :left]
    assert RingBuffer.to_list(right) == [:b, :right]
    assert {:ok, :left} = RingBuffer.peek_newest(left)
    assert {:ok, :right} = RingBuffer.peek_newest(right)
  end

  test "nil is stored and reported like any other pushed item" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(nil)
      |> RingBuffer.push(:b)

    assert RingBuffer.size(buf) == 2
    assert RingBuffer.to_list(buf) == [nil, :b]
    assert {:ok, nil} = RingBuffer.peek_oldest(buf)
    assert {:ok, :b} = RingBuffer.peek_newest(buf)

    buf =
      buf
      |> RingBuffer.push(:c)
      |> RingBuffer.push(nil)

    assert RingBuffer.size(buf) == 3
    assert RingBuffer.to_list(buf) == [:b, :c, nil]
    assert {:ok, nil} = RingBuffer.peek_newest(buf)
    assert {:ok, :b} = RingBuffer.peek_oldest(buf)
  end

  test "backing store is a pre-allocated tuple with one slot per capacity unit" do
    cap = 5
    empty = RingBuffer.new(cap)

    fixed_tuples = fn buf ->
      buf
      |> Map.from_struct()
      |> Map.values()
      |> Enum.filter(fn value -> is_tuple(value) and tuple_size(value) == cap end)
    end

    # Pre-allocated at construction time, before anything was ever pushed.
    assert fixed_tuples.(empty) != []

    full = Enum.reduce(1..(cap * 3), empty, fn i, b -> RingBuffer.push(b, i) end)

    # Still exactly `capacity` slots after many wrapping overwrites.
    assert fixed_tuples.(full) != []
    assert RingBuffer.size(full) == cap
    assert RingBuffer.to_list(full) == [11, 12, 13, 14, 15]
  end
end
```
