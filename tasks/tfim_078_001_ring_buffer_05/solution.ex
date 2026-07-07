  test "new buffer returns empty list" do
    buf = RingBuffer.new(4)
    assert [] = RingBuffer.to_list(buf)
  end