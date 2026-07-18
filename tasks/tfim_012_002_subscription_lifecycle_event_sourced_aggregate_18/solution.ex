  test "events returns full ordered history", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :subscription_created,
             :subscription_activated,
             :subscription_suspended
           ]
  end