  test "cancel on already-cancelled subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:error, :already_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
  end