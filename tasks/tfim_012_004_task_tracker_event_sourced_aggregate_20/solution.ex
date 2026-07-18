  test "events returns full ordered history", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    events = TaskAggregate.events(agg, "task:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :task_created,
             :task_assigned,
             :task_started
           ]
  end