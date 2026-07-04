  test "deposit on unopened account fails", %{agg: agg} do
    assert {:error, :account_not_open} = Aggregate.execute(agg, "acct:1", {:deposit, 100})
  end