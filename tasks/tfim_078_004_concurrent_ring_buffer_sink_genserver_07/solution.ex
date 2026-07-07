  test "flush returns current items and empties the buffer" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 5)
    Enum.each([:a, :b, :c], &ConcurrentRingBuffer.push(pid, &1))

    assert ConcurrentRingBuffer.flush(pid) == [:a, :b, :c]
    assert ConcurrentRingBuffer.size(pid) == 0
    assert ConcurrentRingBuffer.to_list(pid) == []
    assert :error = ConcurrentRingBuffer.peek_oldest(pid)
  end