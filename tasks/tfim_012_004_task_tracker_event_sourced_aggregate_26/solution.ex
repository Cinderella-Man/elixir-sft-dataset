  test "events carry relevant data", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    [created, assigned, started] = TaskAggregate.events(agg, "task:1")

    assert created.type == :task_created
    assert Map.has_key?(created, :title)
    assert Map.has_key?(created, :priority)

    assert assigned.type == :task_assigned
    assert assigned.assignee == "Alice"

    assert started.type == :task_started
  end