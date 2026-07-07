  test "to_list returns items in insertion order when under capacity" do
    buf =
      RingBuffer.new(5)
      |> RingBuffer.push(1)
      |> RingBuffer.push(2)
      |> RingBuffer.push(3)

    assert RingBuffer.to_list(buf) == [1, 2, 3]
  end