  test "assign sets the assignee", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert event.type == :task_assigned

    state = TaskAggregate.state(agg, "task:1")
    assert state.assignee == "Alice"
  end