  test "withdraw decreases the balance", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 500})
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:withdraw, 200})
    assert event.type == :amount_withdrawn

    assert Aggregate.state(agg, "acct:1").balance == 300
  end