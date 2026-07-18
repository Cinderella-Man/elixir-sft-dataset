  test "start on unassigned task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert {:error, :not_assigned} = TaskAggregate.execute(agg, "task:1", {:start})
  end