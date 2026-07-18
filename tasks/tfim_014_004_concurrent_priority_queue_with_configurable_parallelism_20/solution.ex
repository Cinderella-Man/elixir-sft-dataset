  test "start_link rejects non-integer max_concurrency values" do
    assert_raise ArgumentError, fn -> ConcurrentPriorityQueue.start_link(max_concurrency: 2.5) end

    assert_raise ArgumentError, fn ->
      ConcurrentPriorityQueue.start_link(max_concurrency: :two)
    end

    assert_raise ArgumentError, fn -> ConcurrentPriorityQueue.start_link(max_concurrency: "3") end
  end