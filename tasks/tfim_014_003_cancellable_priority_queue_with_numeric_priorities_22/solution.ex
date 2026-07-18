  test "start_link registers the process under the given name option" do
    name = :cancellable_priority_queue_named_audit
    {:ok, pid} = CancellablePriorityQueue.start_link(name: name, processor: fn t -> {:ok, t} end)

    assert Process.whereis(name) == pid

    assert {:ok, ref} = CancellablePriorityQueue.enqueue(name, "via_name", 0)
    assert is_reference(ref)
    assert :ok = CancellablePriorityQueue.drain(name)

    assert CancellablePriorityQueue.processed(name) == [{"via_name", {:ok, "via_name"}}]
    assert CancellablePriorityQueue.status(name) == %{pending: 0, by_priority: %{}, cancelled: 0}
  end