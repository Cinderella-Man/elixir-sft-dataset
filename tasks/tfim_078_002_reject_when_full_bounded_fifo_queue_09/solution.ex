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