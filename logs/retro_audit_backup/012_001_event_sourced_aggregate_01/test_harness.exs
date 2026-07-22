defmodule AggregateTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Aggregate.start_link([])
    %{agg: pid}
  end

  # -------------------------------------------------------
  # Opening an account
  # -------------------------------------------------------

  test "open produces an :account_opened event", %{agg: agg} do
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert event.type == :account_opened
  end

  test "state after open has correct name, balance, and status", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})

    state = Aggregate.state(agg, "acct:1")
    assert state.name == "Alice"
    assert state.balance == 0
    assert state.status == :open
  end

  test "opening an already-open account fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:error, :already_open} = Aggregate.execute(agg, "acct:1", {:open, "Bob"})
  end

  # -------------------------------------------------------
  # Deposits
  # -------------------------------------------------------

  test "deposit increases the balance", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:deposit, 500})
    assert event.type == :amount_deposited

    state = Aggregate.state(agg, "acct:1")
    assert state.balance == 500
  end

  test "multiple deposits accumulate", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    Aggregate.execute(agg, "acct:1", {:deposit, 250})

    assert Aggregate.state(agg, "acct:1").balance == 350
  end

  test "deposit on unopened account fails", %{agg: agg} do
    assert {:error, :account_not_open} = Aggregate.execute(agg, "acct:1", {:deposit, 100})
  end

  test "deposit of zero or negative amount fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:deposit, 0})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:deposit, -50})
  end

  # -------------------------------------------------------
  # Withdrawals
  # -------------------------------------------------------

  test "withdraw decreases the balance", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 500})
    assert {:ok, [event]} = Aggregate.execute(agg, "acct:1", {:withdraw, 200})
    assert event.type == :amount_withdrawn

    assert Aggregate.state(agg, "acct:1").balance == 300
  end

  test "withdraw exact balance succeeds and leaves zero", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    assert {:ok, _} = Aggregate.execute(agg, "acct:1", {:withdraw, 100})

    assert Aggregate.state(agg, "acct:1").balance == 0
  end

  test "withdraw more than balance fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})

    assert {:error, :insufficient_balance} =
             Aggregate.execute(agg, "acct:1", {:withdraw, 101})

    # Balance unchanged after failed withdrawal
    assert Aggregate.state(agg, "acct:1").balance == 100
  end

  test "withdraw on unopened account fails", %{agg: agg} do
    assert {:error, :account_not_open} = Aggregate.execute(agg, "acct:1", {:withdraw, 50})
  end

  test "withdraw of zero or negative amount fails", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 100})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:withdraw, 0})
    assert {:error, :invalid_amount} = Aggregate.execute(agg, "acct:1", {:withdraw, -10})
  end

  # -------------------------------------------------------
  # Event history
  # -------------------------------------------------------

  test "events returns full ordered history", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 200})
    Aggregate.execute(agg, "acct:1", {:withdraw, 50})

    events = Aggregate.events(agg, "acct:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :account_opened,
             :amount_deposited,
             :amount_withdrawn
           ]
  end

  test "failed commands produce no events", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:withdraw, 999})
    Aggregate.execute(agg, "acct:1", {:deposit, -5})

    events = Aggregate.events(agg, "acct:1")
    assert length(events) == 1
    assert hd(events).type == :account_opened
  end

  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert Aggregate.events(agg, "nonexistent") == []
  end

  # -------------------------------------------------------
  # State queries
  # -------------------------------------------------------

  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert Aggregate.state(agg, "nonexistent") == nil
  end

  # -------------------------------------------------------
  # Aggregate independence
  # -------------------------------------------------------

  test "different aggregate ids are completely independent", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 1_000})

    Aggregate.execute(agg, "acct:2", {:open, "Bob"})
    Aggregate.execute(agg, "acct:2", {:deposit, 50})

    assert Aggregate.state(agg, "acct:1").balance == 1_000
    assert Aggregate.state(agg, "acct:2").balance == 50

    assert length(Aggregate.events(agg, "acct:1")) == 2
    assert length(Aggregate.events(agg, "acct:2")) == 2
  end

  # -------------------------------------------------------
  # Full scenario — replay verification
  # -------------------------------------------------------

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

  # -------------------------------------------------------
  # Event content
  # -------------------------------------------------------

  test "events carry relevant data", %{agg: agg} do
    Aggregate.execute(agg, "acct:1", {:open, "Alice"})
    Aggregate.execute(agg, "acct:1", {:deposit, 200})
    Aggregate.execute(agg, "acct:1", {:withdraw, 75})

    [opened, deposited, withdrawn] = Aggregate.events(agg, "acct:1")

    assert opened.type == :account_opened
    assert Map.has_key?(opened, :name) or Map.has_key?(opened, :account_name)

    assert deposited.type == :amount_deposited
    assert deposited.amount == 200

    assert withdrawn.type == :amount_withdrawn
    assert withdrawn.amount == 75
  end
end
