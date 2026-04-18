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
    buf = RingBuffer.new(4)
    buf = RingBuffer.push(buf, :a)
    assert RingBuffer.size(buf) == 1
    buf = RingBuffer.push(buf, :b)
    assert RingBuffer.size(buf) == 2
    buf = RingBuffer.push(buf, :c)
    assert RingBuffer.size(buf) == 3
    buf = RingBuffer.push(buf, :d)
    assert RingBuffer.size(buf) == 4
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
end
