  test "start moves status to :in_progress", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:start})
    assert event.type == :task_started

    assert TaskAggregate.state(agg, "task:1").status == :in_progress
  end