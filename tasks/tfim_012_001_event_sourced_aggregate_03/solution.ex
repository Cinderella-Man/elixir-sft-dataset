  test "state after open has correct name, balance, and status", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})

    state = Aggregate.state(agg, "acct:1")
    assert state.name == "Alice"
    assert state.balance == 0
    assert state.status == :open
  end