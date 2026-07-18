  test "complete moves status to :completed", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:complete})
    assert event.type == :task_completed

    assert TaskAggregate.state(agg, "task:1").status == :completed
  end