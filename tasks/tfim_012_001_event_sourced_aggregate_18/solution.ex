  test "different aggregate ids are completely independent", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 1_000})

    Aggregate.execute(agg, "acct:2", {:open, "Bob"})
    Aggregate.execute(agg, "acct:2", {:deposit, 50})

    assert Aggregate.state(agg, "acct:1").balance == 1_000
    assert Aggregate.state(agg, "acct:2").balance == 50

    assert length(Aggregate.events(agg, "acct:1")) == 2
    assert length(Aggregate.events(agg, "acct:2")) == 2
  end