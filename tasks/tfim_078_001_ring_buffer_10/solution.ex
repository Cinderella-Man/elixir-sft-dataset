  test "size does not exceed capacity" do
    buf = RingBuffer.new(3)
    buf = buf |> RingBuffer.push(:a) |> RingBuffer.push(:b) |> RingBuffer.push(:c)
    assert RingBuffer.size(buf) == 3

    # Push one more — size must stay at 3
    buf = RingBuffer.push(buf, :d)
    assert RingBuffer.size(buf) == 3
  end