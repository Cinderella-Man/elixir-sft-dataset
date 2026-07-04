  test "suspend on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end