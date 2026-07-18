  test "withdraw on unopened account fails", %{agg: agg} do
    assert {:error, :account_not_open} = Aggregate.execute(agg, "acct:1", {:withdraw, 50})
  end