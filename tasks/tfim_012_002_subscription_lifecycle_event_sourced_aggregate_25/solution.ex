  test "cancel from pending succeeds since only cancelled state blocks cancel", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert event.type == :subscription_cancelled
    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end