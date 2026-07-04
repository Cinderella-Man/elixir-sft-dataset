  test "withdraw more than balance fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})

    assert {:error, :insufficient_balance} =
             Aggregate.execute(agg, "acct:1", {:withdraw, 101})

    # Balance unchanged after failed withdrawal
    assert Aggregate.state(agg, "acct:1").balance == 100
  end