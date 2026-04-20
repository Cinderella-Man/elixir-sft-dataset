defmodule SubscriptionAggregateTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = SubscriptionAggregate.start_link([])
    %{agg: pid}
  end

  # -------------------------------------------------------
  # Creating a subscription
  # -------------------------------------------------------

  test "create produces a :subscription_created event", %{agg: agg} do
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert event.type == :subscription_created
  end

  test "state after create has correct plan, status, and reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.plan == "premium"
    assert state.status == :pending
    assert state.reason == nil
  end

  test "creating an already-existing subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert {:error, :already_exists} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "basic"})
  end

  # -------------------------------------------------------
  # Activating a subscription
  # -------------------------------------------------------

  test "activate moves status to :active", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert event.type == :subscription_activated

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :active
  end

  test "activate on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
  end

  test "activate on already-active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_pending} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
  end

  # -------------------------------------------------------
  # Suspending a subscription
  # -------------------------------------------------------

  test "suspend moves status to :suspended with reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})
    assert event.type == :subscription_suspended

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :suspended
    assert state.reason == "payment_failed"
  end

  test "suspend on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end

  test "suspend on pending subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert {:error, :not_active} = SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end

  # -------------------------------------------------------
  # Cancelling a subscription
  # -------------------------------------------------------

  test "cancel moves status to :cancelled", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert event.type == :subscription_cancelled

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end

  test "cancel on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
  end

  test "cancel on already-cancelled subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:error, :already_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
  end

  test "cancel from suspended state succeeds", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "overdue"})
    assert {:ok, _} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end

  # -------------------------------------------------------
  # Reactivating a subscription
  # -------------------------------------------------------

  test "reactivate moves cancelled subscription to :active", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
    assert event.type == :subscription_reactivated

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :active
    assert state.reason == nil
  end

  test "reactivate on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
  end

  test "reactivate on active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
  end

  # -------------------------------------------------------
  # Event history
  # -------------------------------------------------------

  test "events returns full ordered history", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :subscription_created,
             :subscription_activated,
             :subscription_suspended
           ]
  end

  test "failed commands produce no events", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 1
    assert hd(events).type == :subscription_created
  end

  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert SubscriptionAggregate.events(agg, "nonexistent") == []
  end

  # -------------------------------------------------------
  # State queries
  # -------------------------------------------------------

  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert SubscriptionAggregate.state(agg, "nonexistent") == nil
  end

  # -------------------------------------------------------
  # Aggregate independence
  # -------------------------------------------------------

  test "different aggregate ids are completely independent", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    SubscriptionAggregate.execute(agg, "sub:2", {:create, "basic"})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :active
    assert SubscriptionAggregate.state(agg, "sub:2").status == :pending

    assert length(SubscriptionAggregate.events(agg, "sub:1")) == 2
    assert length(SubscriptionAggregate.events(agg, "sub:2")) == 1
  end

  # -------------------------------------------------------
  # Full scenario — replay verification
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Event content
  # -------------------------------------------------------

  test "events carry relevant data", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    [created, activated, suspended] = SubscriptionAggregate.events(agg, "sub:1")

    assert created.type == :subscription_created
    assert Map.has_key?(created, :plan)

    assert activated.type == :subscription_activated

    assert suspended.type == :subscription_suspended
    assert suspended.reason == "payment_failed"
  end
end
