  test "suspend moves status to :suspended with reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    assert {:ok, [event]} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    assert event.type == :subscription_suspended

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :suspended
    assert state.reason == "payment_failed"
  end