  test "new buffer has size 0" do
    buf = RingBuffer.new(4)
    assert RingBuffer.size(buf) == 0
  end