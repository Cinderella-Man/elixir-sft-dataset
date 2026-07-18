  test "events carry relevant data", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    [created, activated, suspended] = SubscriptionAggregate.events(agg, "sub:1")

    assert created.type == :subscription_created
    assert Map.has_key?(created, :plan)

    assert activated.type == :subscription_activated

    assert suspended.type == :subscription_suspended
    assert suspended.reason == "payment_failed"
  end