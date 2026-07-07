  test "to_list at exactly full capacity returns all items" do
    buf =
      RingBuffer.new(3)
      |> RingBuffer.push(:a)
      |> RingBuffer.push(:b)
      |> RingBuffer.push(:c)

    assert RingBuffer.to_list(buf) == [:a, :b, :c]
  end