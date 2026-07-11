  test "capacity is enforced per queue and rejects when full (nothing stored)", %{} do
    {:ok, dlq} = PriorityDLQ.start_link(clock: &Clock.now/0, capacity: 2)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :a, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :b, :err, %{}, :low)
    assert {:error, :full} = PriorityDLQ.push(dlq, "q", :c, :err, %{}, :high)
    assert length(PriorityDLQ.peek(dlq, "q", 10)) == 2

    # other queue has its own budget
    assert {:ok, _} = PriorityDLQ.push(dlq, "other", :d, :err, %{}, :low)
  end