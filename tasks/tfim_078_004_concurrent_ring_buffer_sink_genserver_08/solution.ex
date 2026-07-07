  test "flush on an empty buffer returns []" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    assert ConcurrentRingBuffer.flush(pid) == []
  end