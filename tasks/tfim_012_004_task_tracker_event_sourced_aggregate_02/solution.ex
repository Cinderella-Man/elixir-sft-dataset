  test "create produces a :task_created event", %{agg: agg} do
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert event.type == :task_created
  end