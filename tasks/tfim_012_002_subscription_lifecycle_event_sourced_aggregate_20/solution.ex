  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert SubscriptionAggregate.events(agg, "nonexistent") == []
  end