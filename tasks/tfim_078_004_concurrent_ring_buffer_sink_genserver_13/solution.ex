  test "works with mixed value types" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 5)
    Enum.each([42, "hello", :atom, {:tuple, 1}, [1, 2, 3]], &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.to_list(pid) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end