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