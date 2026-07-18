  test "registers under the given :name and is reachable by that name" do
    name = :priority_queue_named_registration_test

    {:ok, _pid} =
      PriorityQueue.start_link(name: name, processor: fn t -> {:ok, t} end)

    assert :ok = PriorityQueue.enqueue(name, "named_task", :high)
    assert :ok = PriorityQueue.drain(name)

    assert PriorityQueue.processed(name) == [{"named_task", {:ok, "named_task"}}]
  end