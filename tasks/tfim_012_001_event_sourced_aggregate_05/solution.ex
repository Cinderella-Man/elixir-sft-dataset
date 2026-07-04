  test "deposit increases the balance", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:deposit, 500})
    assert event.type == :amount_deposited

    state = Aggregate.state(agg, "acct:1")
    assert state.balance == 500
  end