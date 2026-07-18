  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = Aggregate.execute(agg, "a", {:open, "Charlie"})
    {:ok, _} = Aggregate.execute(agg, "a", {:deposit, 500})
    {:ok, _} = Aggregate.execute(agg, "a", {:deposit, 300})
    {:error, :insufficient_balance} = Aggregate.execute(agg, "a", {:withdraw, 900})
    {:ok, _} = Aggregate.execute(agg, "a", {:withdraw, 150})
    {:ok, _} = Aggregate.execute(agg, "a", {:deposit, 50})
    {:ok, _} = Aggregate.execute(agg, "a", {:withdraw, 700})

    state = Aggregate.state(agg, "a")
    assert state.name == "Charlie"
    assert state.balance == 0
    assert state.status == :open

    events = Aggregate.events(agg, "a")
    # 5 successful commands = 5 events (open, dep, dep, withdraw, dep, withdraw)
    assert length(events) == 6

    types = Enum.map(events, & &1.type)

    assert types == [
             :account_opened,
             :amount_deposited,
             :amount_deposited,
             :amount_withdrawn,
             :amount_deposited,
             :amount_withdrawn
           ]
  end