  test "peek_newest reflects the latest push after overwrites" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(10)
      |> RingBuffer.push(20)
      |> RingBuffer.push(30)
      |> RingBuffer.push(40)

    assert {:ok, 40} = RingBuffer.peek_newest(buf)
  end