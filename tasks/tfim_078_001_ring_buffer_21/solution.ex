  test "nil is stored and reported like any other pushed item" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(nil)
      |> RingBuffer.push(:b)

    assert RingBuffer.size(buf) == 2
    assert RingBuffer.to_list(buf) == [nil, :b]
    assert {:ok, nil} = RingBuffer.peek_oldest(buf)
    assert {:ok, :b} = RingBuffer.peek_newest(buf)

    buf =
      buf
      |> RingBuffer.push(:c)
      |> RingBuffer.push(nil)

    assert RingBuffer.size(buf) == 3
    assert RingBuffer.to_list(buf) == [:b, :c, nil]
    assert {:ok, nil} = RingBuffer.peek_newest(buf)
    assert {:ok, :b} = RingBuffer.peek_oldest(buf)
  end