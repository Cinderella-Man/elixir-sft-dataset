  test "withdraw of zero or negative amount fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:withdraw, 0})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:withdraw, -10})
  end