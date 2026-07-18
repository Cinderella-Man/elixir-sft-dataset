  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert SubscriptionAggregate.state(agg, "nonexistent") == nil
  end