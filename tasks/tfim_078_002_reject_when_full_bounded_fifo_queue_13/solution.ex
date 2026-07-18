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