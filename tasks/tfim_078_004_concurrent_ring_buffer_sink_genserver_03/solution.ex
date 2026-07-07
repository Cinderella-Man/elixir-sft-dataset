  test "can be registered by name" do
    {:ok, _pid} = ConcurrentRingBuffer.start_link(capacity: 3, name: :ring_named)
    ConcurrentRingBuffer.push(:ring_named, :a)
    ConcurrentRingBuffer.push(:ring_named, :b)
    assert ConcurrentRingBuffer.to_list(:ring_named) == [:a, :b]
  end