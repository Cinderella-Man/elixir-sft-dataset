  test "capacity-1 buffer accepts then rejects until popped" do
    buf = RejectingRingBuffer.new(1)
    {:ok, buf} = RejectingRingBuffer.push(buf, :only)
    assert {:error, :full} = RejectingRingBuffer.push(buf, :nope)
    {:ok, :only, buf} = RejectingRingBuffer.pop(buf)
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :again)
    assert RejectingRingBuffer.to_list(buf) == [:again]
  end