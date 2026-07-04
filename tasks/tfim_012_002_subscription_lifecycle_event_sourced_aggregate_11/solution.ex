  test "cancel moves status to :cancelled", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert event.type == :subscription_cancelled

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end