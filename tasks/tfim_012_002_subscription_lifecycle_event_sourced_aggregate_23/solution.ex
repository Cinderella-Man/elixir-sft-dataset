  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:create, "gold"})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:activate})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:suspend, "payment_overdue"})
    {:error, :not_active} = SubscriptionAggregate.execute(agg, "a", {:suspend, "duplicate"})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:cancel})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:reactivate})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:cancel})

    state = SubscriptionAggregate.state(agg, "a")
    assert state.plan == "gold"
    assert state.status == :cancelled
    assert state.reason == nil

    events = SubscriptionAggregate.events(agg, "a")
    # 6 successful commands = 6 events
    assert length(events) == 6

    types = Enum.map(events, & &1.type)

    assert types == [
             :subscription_created,
             :subscription_activated,
             :subscription_suspended,
             :subscription_cancelled,
             :subscription_reactivated,
             :subscription_cancelled
           ]
  end