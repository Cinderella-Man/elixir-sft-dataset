  test "oldest item is overwritten when full" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    Enum.each([1, 2, 3, 4], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.size(pid) == 3
    assert ConcurrentRingBuffer.to_list(pid) == [2, 3, 4]
    assert {:ok, 2} = ConcurrentRingBuffer.peek_oldest(pid)
    assert {:ok, 4} = ConcurrentRingBuffer.peek_newest(pid)
  end