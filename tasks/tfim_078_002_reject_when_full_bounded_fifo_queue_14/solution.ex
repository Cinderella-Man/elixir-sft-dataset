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