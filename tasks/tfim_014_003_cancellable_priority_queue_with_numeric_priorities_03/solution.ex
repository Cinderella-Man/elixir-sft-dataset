  test "enqueue returns unique refs", %{pq: pq} do
    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq, "a", 0)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq, "b", 0)
    {:ok, ref3} = CancellablePriorityQueue.enqueue(pq, "c", 1)

    assert ref1 != ref2
    assert ref2 != ref3
    assert ref1 != ref3
  end