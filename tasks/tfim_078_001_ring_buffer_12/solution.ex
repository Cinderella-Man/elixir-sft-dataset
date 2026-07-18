  test "oldest item is overwritten when buffer is full" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(1)
      |> RingBuffer.push(2)
      |> RingBuffer.push(3)
      |> RingBuffer.push(4)

    # 1 should be gone; list should be oldest-first
    assert RingBuffer.to_list(buf) == [2, 3, 4]
  end