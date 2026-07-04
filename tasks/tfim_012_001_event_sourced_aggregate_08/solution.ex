  test "deposit of zero or negative amount fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:deposit, 0})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:deposit, -50})
  end