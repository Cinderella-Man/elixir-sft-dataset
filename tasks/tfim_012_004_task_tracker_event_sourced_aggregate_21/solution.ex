  test "failed commands produce no events", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})

    events = TaskAggregate.events(agg, "task:1")
    assert length(events) == 1
    assert hd(events).type == :task_created
  end