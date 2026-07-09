  test "suspend on pending subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    assert {:error, :not_active} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end