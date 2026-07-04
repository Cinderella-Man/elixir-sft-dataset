  test "activate moves status to :active", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert event.type == :subscription_activated

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :active
  end