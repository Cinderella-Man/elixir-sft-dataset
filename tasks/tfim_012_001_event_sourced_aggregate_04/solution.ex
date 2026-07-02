  test "opening an already-open account fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:error, :already_open} = Aggregate.execute(agg, "acct:1", {:open, "Bob"})
  end