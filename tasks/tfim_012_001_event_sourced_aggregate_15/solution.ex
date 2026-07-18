  test "failed commands produce no events", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:withdraw, 999})
    Aggregate.execute(agg, "acct:1", {:deposit, -5})

    events = Aggregate.events(agg, "acct:1")
    assert length(events) == 1
    assert hd(events).type == :account_opened
  end