  test "different aggregate ids are completely independent", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    SubscriptionAggregate.execute(agg, "sub:2", {:create, "basic"})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :active
    assert SubscriptionAggregate.state(agg, "sub:2").status == :pending

    assert length(SubscriptionAggregate.events(agg, "sub:1")) == 2
    assert length(SubscriptionAggregate.events(agg, "sub:2")) == 1
  end