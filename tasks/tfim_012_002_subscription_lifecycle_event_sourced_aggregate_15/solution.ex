  test "reactivate moves cancelled subscription to :active", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
    assert event.type == :subscription_reactivated

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :active
    assert state.reason == nil
  end