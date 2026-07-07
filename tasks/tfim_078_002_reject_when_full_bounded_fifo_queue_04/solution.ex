  test "push returns {:ok, buffer} and grows size" do
    buf = RejectingRingBuffer.new(3)
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :a)
    assert RejectingRingBuffer.size(buf) == 1
    assert {:ok, buf} = RejectingRingBuffer.push(buf, :b)
    assert RejectingRingBuffer.size(buf) == 2
    assert RejectingRingBuffer.to_list(buf) == [:a, :b]
  end