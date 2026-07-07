  test "size grows with each push up to capacity" do
    buf = RingBuffer.new(4)
    buf = RingBuffer.push(buf, :a)
    assert RingBuffer.size(buf) == 1
    buf = RingBuffer.push(buf, :b)
    assert RingBuffer.size(buf) == 2
    buf = RingBuffer.push(buf, :c)
    assert RingBuffer.size(buf) == 3
    buf = RingBuffer.push(buf, :d)
    assert RingBuffer.size(buf) == 4
  end