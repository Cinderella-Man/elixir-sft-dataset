  test "many overwrites keep only the last capacity items" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 4)
    Enum.each(1..20, &ConcurrentRingBuffer.push(pid, &1))
    assert ConcurrentRingBuffer.size(pid) == 4
    assert ConcurrentRingBuffer.to_list(pid) == [17, 18, 19, 20]
  end