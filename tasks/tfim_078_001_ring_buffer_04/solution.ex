  test "new buffer returns :error for peek_newest" do
    buf = RingBuffer.new(4)
    assert :error = RingBuffer.peek_newest(buf)
  end