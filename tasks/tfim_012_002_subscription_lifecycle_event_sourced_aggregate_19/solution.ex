  test "failed commands produce no events", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    # Both of the following fail against a :pending subscription and must add no events.
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
    SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 1
    assert hd(events).type == :subscription_created
  end