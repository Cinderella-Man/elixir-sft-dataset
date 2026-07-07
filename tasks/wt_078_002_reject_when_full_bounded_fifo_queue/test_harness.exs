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
end
