  test "assign on completed task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})
    assert {:error, :already_completed} = TaskAggregate.execute(agg, "task:1", {:assign, "Bob"})
  end