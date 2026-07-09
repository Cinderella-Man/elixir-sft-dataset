  test "creating an already-existing task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})

    assert {:error, :already_exists} =
             TaskAggregate.execute(agg, "task:1", {:create, "Other", :low})
  end