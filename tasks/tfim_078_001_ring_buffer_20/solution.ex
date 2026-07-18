  test "push leaves the source buffer untouched and branches independently" do
    base =
      RingBuffer.new(2)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)

    left = RingBuffer.push(base, :left)
    right = RingBuffer.push(base, :right)

    assert RingBuffer.to_list(base) == [:a, :b]
    assert RingBuffer.size(base) == 2
    assert {:ok, :a} = RingBuffer.peek_oldest(base)
    assert {:ok, :b} = RingBuffer.peek_newest(base)

    assert RingBuffer.to_list(left) == [:b, :left]
    assert RingBuffer.to_list(right) == [:b, :right]
    assert {:ok, :left} = RingBuffer.peek_newest(left)
    assert {:ok, :right} = RingBuffer.peek_newest(right)
  end