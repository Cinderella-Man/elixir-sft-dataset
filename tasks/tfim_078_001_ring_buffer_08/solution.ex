  test "peek_oldest returns the first item pushed" do
    buf =
      RingBuffer.new(4)
      |> RingBuffer.push(:first)
      |> RingBuffer.push(:second)
      |> RingBuffer.push(:third)

    assert {:ok, :first} = RingBuffer.peek_oldest(buf)
  end