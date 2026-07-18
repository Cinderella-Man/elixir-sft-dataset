  test "buffer drained after wraparound reports empty on every reader" do
    buf = RejectingRingBuffer.new(2)
    {:ok, buf} = RejectingRingBuffer.push(buf, 1)
    {:ok, buf} = RejectingRingBuffer.push(buf, 2)
    {:ok, 1, buf} = RejectingRingBuffer.pop(buf)
    {:ok, buf} = RejectingRingBuffer.push(buf, 3)
    {:ok, 2, buf} = RejectingRingBuffer.pop(buf)
    {:ok, 3, buf} = RejectingRingBuffer.pop(buf)

    assert RejectingRingBuffer.size(buf) == 0
    refute RejectingRingBuffer.full?(buf)
    assert RejectingRingBuffer.to_list(buf) == []
    assert :error = RejectingRingBuffer.peek_oldest(buf)
    assert :error = RejectingRingBuffer.peek_newest(buf)
    assert :empty = RejectingRingBuffer.pop(buf)
  end