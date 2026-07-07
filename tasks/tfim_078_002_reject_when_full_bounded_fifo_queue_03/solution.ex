  test "new buffer returns :error for peeks and :empty for pop" do
    buf = RejectingRingBuffer.new(4)
    assert :error = RejectingRingBuffer.peek_oldest(buf)
    assert :error = RejectingRingBuffer.peek_newest(buf)
    assert :empty = RejectingRingBuffer.pop(buf)
    assert [] = RejectingRingBuffer.to_list(buf)
  end