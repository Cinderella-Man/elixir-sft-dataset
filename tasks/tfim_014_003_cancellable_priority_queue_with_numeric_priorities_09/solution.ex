  test "cancel returns error for already processed task", %{pq: pq} do
    {:ok, ref} = CancellablePriorityQueue.enqueue(pq, "fast", 0)
    CancellablePriorityQueue.drain(pq)

    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq, ref)
  end