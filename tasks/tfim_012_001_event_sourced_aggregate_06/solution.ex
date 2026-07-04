  test "multiple deposits accumulate", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    Aggregate.execute(agg, "acct:1", {:deposit, 250})

    assert Aggregate.state(agg, "acct:1").balance == 350
  end