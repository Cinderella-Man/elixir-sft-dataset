  test "buffer is usable again after flush (wraparound preserved)" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 3)
    Enum.each([1, 2, 3, 4], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.flush(pid) == [2, 3, 4]

    Enum.each([5, 6], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.to_list(pid) == [5, 6]
  end