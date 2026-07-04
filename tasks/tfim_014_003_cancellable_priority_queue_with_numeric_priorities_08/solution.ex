  test "cancel returns error for unknown ref", %{pq: pq} do
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq, make_ref())
  end