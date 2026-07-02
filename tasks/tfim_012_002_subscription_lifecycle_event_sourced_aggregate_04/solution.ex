  test "creating an already-existing subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert {:error, :already_exists} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "basic"})
  end