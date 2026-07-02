  test "open produces an :account_opened event", %{agg: agg} do
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert event.type == :account_opened
  end