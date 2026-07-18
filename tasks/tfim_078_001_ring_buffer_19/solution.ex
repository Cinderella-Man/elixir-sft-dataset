  test "peek_newest is correct when the write head wraps to slot zero" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)

    # Exactly full: the write head has wrapped back to slot 0.
    assert {:ok, :c} = RingBuffer.peek_newest(buf)
    assert {:ok, :a} = RingBuffer.peek_oldest(buf)
    assert RingBuffer.to_list(buf) == [:a, :b, :c]

    # One complete extra cycle: read and write heads coincide again while full.
    buf =
      buf
      |> RingBuffer.push(:d)
      |> RingBuffer.push(:e)
      |> RingBuffer.push(:f)

    assert RingBuffer.size(buf) == 3
    assert {:ok, :f} = RingBuffer.peek_newest(buf)
    assert {:ok, :d} = RingBuffer.peek_oldest(buf)
    assert RingBuffer.to_list(buf) == [:d, :e, :f]
  end