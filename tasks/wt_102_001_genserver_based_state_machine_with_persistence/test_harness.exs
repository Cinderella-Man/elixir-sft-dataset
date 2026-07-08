defmodule StateMachineTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Real repo: the test environment provides StateMachine.Repo (SQLite),
  # already configured, with this bundle's migration applied. Persistence,
  # query filtering, and order_by are enforced by a real query engine.
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(StateMachine.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Starting entities
  # ---------------------------------------------------------------------------

  test "start/2 returns :pending for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 for the same entity twice returns the same state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 re-hydrates state from DB after the in-memory map is cleared", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:42")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:42", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:42", :ship)

    # Start a *new* GenServer backed by the same database
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Entity was never started in sm2, so it must hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:42")
  end

  # ---------------------------------------------------------------------------
  # get_state
  # ---------------------------------------------------------------------------

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "order:nope")
  end

  test "get_state/2 reflects the current in-memory state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Happy-path transitions
  # ---------------------------------------------------------------------------

  test "full happy path: pending → confirmed → shipped → delivered", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    assert {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")

    assert {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :delivered} = StateMachine.transition(sm, "order:1", :deliver)

    assert {:ok, :delivered} = StateMachine.get_state(sm, "order:1")
  end

  test "cancellation from :pending", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:2", :cancel)
  end

  test "cancellation from :confirmed", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:3")
    {:ok, _} = StateMachine.transition(sm, "order:3", :confirm)
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:3", :cancel)
  end

  # ---------------------------------------------------------------------------
  # Invalid transitions
  # ---------------------------------------------------------------------------

  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)

    # :ship from :confirmed is valid, but :deliver from :confirmed is not
    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver)

    # State must be unchanged
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  test "transitioning a terminal state is invalid", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :cancel)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :confirm)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:1")
  end

  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} =
             StateMachine.transition(sm, "order:unknown", :confirm)
  end

  test "invalid transition does not write to DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    {:error, :invalid_transition} =
      StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, []} = StateMachine.history(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Persistence / history
  # ---------------------------------------------------------------------------

  test "history/2 records every transition in order", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")

    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed

    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
  end

  test "history/2 for unknown entity returns empty list", %{sm: sm} do
    assert {:ok, []} = StateMachine.history(sm, "order:nobody")
  end

  test "history/2 is scoped per entity", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:A")
    {:ok, _} = StateMachine.start(sm, "order:B")
    {:ok, _} = StateMachine.transition(sm, "order:A", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:B", :cancel)

    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:A")
    assert {:ok, [%{event: :cancel}]} = StateMachine.history(sm, "order:B")
  end

  # ---------------------------------------------------------------------------
  # State recovery after simulated restart
  # ---------------------------------------------------------------------------

  test "state survives GenServer restart and is recovered from DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:99")
    {:ok, _} = StateMachine.transition(sm, "order:99", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:99", :ship)

    # Kill the original GenServer (simulate crash/restart)
    GenServer.stop(sm)

    # Boot a fresh one backed by the same repo
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Re-hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:99")

    # And it should accept further valid transitions from recovered state
    assert {:ok, :delivered} = StateMachine.transition(sm2, "order:99", :deliver)
  end

  # ---------------------------------------------------------------------------
  # Concurrency — concurrent callers serialize correctly
  # ---------------------------------------------------------------------------

  test "concurrent transitions on the same entity serialize without corruption", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:concurrent")

    # Fire many concurrent callers; only the first :confirm should succeed,
    # the rest should get :invalid_transition (already confirmed) or
    # :invalid_transition (not a valid event from :pending).
    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:concurrent", :confirm)
        end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # Exactly one transition should have succeeded
    assert length(oks) == 1
    assert {:ok, :confirmed} = hd(oks)

    # All others should have gotten :invalid_transition
    assert length(errors) == 19
  end

  test "concurrent transitions on *different* entities don't interfere", %{sm: sm} do
    for i <- 1..10 do
      StateMachine.start(sm, "order:par:#{i}")
    end

    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:par:#{i}", :confirm)
        end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, &match?({:ok, :confirmed}, &1))
  end
end
