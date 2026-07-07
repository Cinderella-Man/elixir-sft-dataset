  test "new buffer has size 0 and is not full" do
    buf = RejectingRingBuffer.new(4)
    assert RejectingRingBuffer.size(buf) == 0
    refute RejectingRingBuffer.full?(buf)
  end