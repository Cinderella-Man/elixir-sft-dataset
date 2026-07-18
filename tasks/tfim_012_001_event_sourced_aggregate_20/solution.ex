  test "events carry relevant data", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 200})
    Aggregate.execute(agg, "acct:1", {:withdraw, 75})

    [opened, deposited, withdrawn] = Aggregate.events(agg, "acct:1")

    assert opened.type == :account_opened
    assert Map.has_key?(opened, :name) or Map.has_key?(opened, :account_name)

    assert deposited.type == :amount_deposited
    assert deposited.amount == 200

    assert withdrawn.type == :amount_withdrawn
    assert withdrawn.amount == 75
  end