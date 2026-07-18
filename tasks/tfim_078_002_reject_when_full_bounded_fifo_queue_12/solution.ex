  test "works with mixed value types" do
    buf = RejectingRingBuffer.new(5)
    {:ok, buf} = RejectingRingBuffer.push(buf, 42)
    {:ok, buf} = RejectingRingBuffer.push(buf, "hello")
    {:ok, buf} = RejectingRingBuffer.push(buf, :atom)
    {:ok, buf} = RejectingRingBuffer.push(buf, {:tuple, 1})
    {:ok, buf} = RejectingRingBuffer.push(buf, [1, 2, 3])

    assert RejectingRingBuffer.to_list(buf) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end