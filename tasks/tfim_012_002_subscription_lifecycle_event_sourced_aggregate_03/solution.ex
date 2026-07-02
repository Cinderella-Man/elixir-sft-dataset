  test "state after create has correct plan, status, and reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.plan == "premium"
    assert state.status == :pending
    assert state.reason == nil
  end