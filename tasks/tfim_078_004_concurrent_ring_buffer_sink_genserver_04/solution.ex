  test "push grows size up to capacity" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    assert :ok = ConcurrentRingBuffer.push(pid, 1)
    assert ConcurrentRingBuffer.size(pid) == 1
    ConcurrentRingBuffer.push(pid, 2)
    ConcurrentRingBuffer.push(pid, 3)
    assert ConcurrentRingBuffer.size(pid) == 3
    assert ConcurrentRingBuffer.to_list(pid) == [1, 2, 3]
  end