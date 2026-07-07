  test "capacity-1 server always holds exactly one item" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 1)
    ConcurrentRingBuffer.push(pid, :only)
    assert ConcurrentRingBuffer.to_list(pid) == [:only]
    ConcurrentRingBuffer.push(pid, :replaced)
    assert ConcurrentRingBuffer.to_list(pid) == [:replaced]
    assert {:ok, :replaced} = ConcurrentRingBuffer.peek_oldest(pid)
    assert {:ok, :replaced} = ConcurrentRingBuffer.peek_newest(pid)
  end