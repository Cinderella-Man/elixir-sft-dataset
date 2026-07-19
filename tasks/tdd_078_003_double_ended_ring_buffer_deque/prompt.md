# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    d = RingDeque.new(3)
    d = RingDeque.push_back(d, :a)
    d = RingDeque.push_back(d, :b)
    d = RingDeque.push_back(d, :c)

    {:ok, :a, d} = RingDeque.pop_front(d)
    {:ok, :b, d} = RingDeque.pop_front(d)
    # head is now deep into the tuple; push_back must wrap
    d = RingDeque.push_back(d, :d)
    d = RingDeque.push_back(d, :e)
    assert RingDeque.to_list(d) == [:c, :d, :e]

    # push_front must also wrap the head backwards
    {:ok, :e, d} = RingDeque.pop_back(d)
    d = RingDeque.push_front(d, :x)
    assert RingDeque.to_list(d) == [:x, :c, :d]
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
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
