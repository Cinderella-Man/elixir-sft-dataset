  test "reassigning to a different person succeeds", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:ok, _} = TaskAggregate.execute(agg, "task:1", {:assign, "Bob"})

    assert TaskAggregate.state(agg, "task:1").assignee == "Bob"
  end