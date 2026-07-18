  test "reopen moves completed task back to :created with nil assignee", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:reopen})
    assert event.type == :task_reopened

    state = TaskAggregate.state(agg, "task:1")
    assert state.status == :created
    assert state.assignee == nil
  end