  test "capacity-1 buffer always holds exactly one item" do
    buf = RingBuffer.new(1)
    assert RingBuffer.size(buf) == 0

    buf = RingBuffer.push(buf, :only)
    assert RingBuffer.size(buf) == 1
    assert {:ok, :only} = RingBuffer.peek_oldest(buf)
    assert {:ok, :only} = RingBuffer.peek_newest(buf)

    buf = RingBuffer.push(buf, :replaced)
    assert RingBuffer.size(buf) == 1
    assert RingBuffer.to_list(buf) == [:replaced]
    assert {:ok, :replaced} = RingBuffer.peek_oldest(buf)
    assert {:ok, :replaced} = RingBuffer.peek_newest(buf)
  end