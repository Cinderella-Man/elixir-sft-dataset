  test "complete on task not in progress fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:error, :not_in_progress} = TaskAggregate.execute(agg, "task:1", {:complete})
  end