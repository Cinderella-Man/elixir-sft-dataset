  test "pop removes items oldest-first" do
    {:ok, buf} = RejectingRingBuffer.new(3) |> RejectingRingBuffer.push(:a)
    {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    {:ok, buf} = RejectingRingBuffer.push(buf, :c)

    assert {:ok, :a, buf} = RejectingRingBuffer.pop(buf)
    assert {:ok, :b, buf} = RejectingRingBuffer.pop(buf)
    assert RejectingRingBuffer.to_list(buf) == [:c]
    assert {:ok, :c, buf} = RejectingRingBuffer.pop(buf)
    assert :empty = RejectingRingBuffer.pop(buf)
  end