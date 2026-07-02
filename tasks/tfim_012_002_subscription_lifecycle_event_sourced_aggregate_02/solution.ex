  test "create produces a :subscription_created event", %{agg: agg} do
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert event.type == :subscription_created
  end