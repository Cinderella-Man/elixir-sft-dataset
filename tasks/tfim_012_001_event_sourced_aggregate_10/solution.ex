  test "withdraw exact balance succeeds and leaves zero", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    assert {:ok, _} = Aggregate.execute(agg, "acct:1", {:withdraw, 100})

    assert Aggregate.state(agg, "acct:1").balance == 0
  end