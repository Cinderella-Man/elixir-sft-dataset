  test "peek_oldest reflects the new oldest after overwrites" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(10)
      |> RingBuffer.push(20)
      |> RingBuffer.push(30)
      |> RingBuffer.push(40)

    assert {:ok, 20} = RingBuffer.peek_oldest(buf)
  end