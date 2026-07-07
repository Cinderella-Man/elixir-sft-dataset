  test "creating with invalid priority fails", %{agg: agg} do
    assert {:error, :invalid_priority} =
             TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :urgent})
  end