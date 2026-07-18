  test "start_link rejects non-positive max_concurrency" do
    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: -1)
    end
  end