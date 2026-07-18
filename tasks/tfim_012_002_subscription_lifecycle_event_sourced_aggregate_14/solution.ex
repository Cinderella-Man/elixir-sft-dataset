  test "cancel from suspended state succeeds", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "overdue"})
    assert {:ok, _} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end