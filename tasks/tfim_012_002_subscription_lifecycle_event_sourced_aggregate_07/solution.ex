  test "activate on already-active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_pending} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
  end