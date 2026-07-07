  test "peek_newest returns the last item pushed" do
    buf =
      RingBuffer.new(4)
      |> RingBuffer.push(:first)
      |> RingBuffer.push(:second)
      |> RingBuffer.push(:third)

    assert {:ok, :third} = RingBuffer.peek_newest(buf)
  end