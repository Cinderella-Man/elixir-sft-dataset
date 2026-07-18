  test "default processor returns the task unchanged when :processor omitted" do
    {:ok, pq2} = PriorityQueue.start_link([])

    assert :ok = PriorityQueue.enqueue(pq2, "echo_me", :normal)
    assert :ok = PriorityQueue.drain(pq2)

    assert PriorityQueue.processed(pq2) == [{"echo_me", "echo_me"}]
  end