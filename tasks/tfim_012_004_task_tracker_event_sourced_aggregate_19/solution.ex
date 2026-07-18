  test "reopen on non-completed task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    # This correctly expects :not_completed
    assert {:error, :not_completed} = TaskAggregate.execute(agg, "task:1", {:reopen})
  end