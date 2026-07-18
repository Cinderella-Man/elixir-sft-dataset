  test "reactivate on active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
  end