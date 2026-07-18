  test "events returns full ordered history", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 200})
    Aggregate.execute(agg, "acct:1", {:withdraw, 50})

    events = Aggregate.events(agg, "acct:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :account_opened,
             :amount_deposited,
             :amount_withdrawn
           ]
  end