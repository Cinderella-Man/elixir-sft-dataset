  test "new buffer returns :error for peek_oldest" do
    buf = RingBuffer.new(4)
    assert :error = RingBuffer.peek_oldest(buf)
  end