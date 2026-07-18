  test "different aggregate ids are completely independent", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    TaskAggregate.execute(agg, "task:2", {:create, "Add feature", :low})

    assert TaskAggregate.state(agg, "task:1").status == :in_progress
    assert TaskAggregate.state(agg, "task:2").status == :created

    assert length(TaskAggregate.events(agg, "task:1")) == 3
    assert length(TaskAggregate.events(agg, "task:2")) == 1
  end