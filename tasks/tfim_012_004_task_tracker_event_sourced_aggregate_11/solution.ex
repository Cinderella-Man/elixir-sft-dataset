  test "start on non-existent task fails", %{agg: agg} do
    assert {:error, :not_found} = TaskAggregate.execute(agg, "task:1", {:start})
  end