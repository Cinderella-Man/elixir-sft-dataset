  test "start on already-in-progress task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    assert {:error, :already_started} = TaskAggregate.execute(agg, "task:1", {:start})
  end