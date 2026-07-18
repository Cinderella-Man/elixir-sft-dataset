  test "many overwrites — only last capacity items survive" do
    capacity = 4

    buf =
      Enum.reduce(1..20, RingBuffer.new(capacity), fn i, b ->
        RingBuffer.push(b, i)
      end)

    assert RingBuffer.size(buf) == capacity
    assert RingBuffer.to_list(buf) == [17, 18, 19, 20]
  end