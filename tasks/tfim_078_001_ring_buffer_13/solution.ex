  test "multiple overwrites maintain correct insertion order" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)
      |> RingBuffer.push(:d)
      |> RingBuffer.push(:e)

    assert RingBuffer.to_list(buf) == [:c, :d, :e]
  end