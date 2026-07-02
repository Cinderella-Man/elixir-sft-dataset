  test "state after create has correct title, assignee, status, and priority", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})

    state = TaskAggregate.state(agg, "task:1")
    assert state.title == "Fix bug"
    assert state.assignee == nil
    assert state.status == :created
    assert state.priority == :high
  end