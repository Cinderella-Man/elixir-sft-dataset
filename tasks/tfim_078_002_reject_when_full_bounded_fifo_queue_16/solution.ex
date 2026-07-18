  test "nil and duplicate items are stored as real values in insertion order" do
    buf = RejectingRingBuffer.new(4)
    {:ok, buf} = RejectingRingBuffer.push(buf, nil)
    {:ok, buf} = RejectingRingBuffer.push(buf, :dup)
    {:ok, buf} = RejectingRingBuffer.push(buf, :dup)
    {:ok, buf} = RejectingRingBuffer.push(buf, nil)

    assert RejectingRingBuffer.size(buf) == 4
    assert RejectingRingBuffer.full?(buf)
    assert RejectingRingBuffer.to_list(buf) == [nil, :dup, :dup, nil]
    assert {:ok, nil} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, nil} = RejectingRingBuffer.peek_newest(buf)
    assert {:error, :full} = RejectingRingBuffer.push(buf, :extra)
    assert {:ok, nil, _} = RejectingRingBuffer.pop(buf)
  end