  test "new server is empty" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    assert ConcurrentRingBuffer.size(pid) == 0
    assert ConcurrentRingBuffer.to_list(pid) == []
    assert :error = ConcurrentRingBuffer.peek_oldest(pid)
    assert :error = ConcurrentRingBuffer.peek_newest(pid)
  end