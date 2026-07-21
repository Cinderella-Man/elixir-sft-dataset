defmodule StateMachineTest.FailingInsertRepo do
  @moduledoc """
  Repo facade used to exercise the DB-write-failure branch.

  Reads (`all/1,2`, `one/1,2`) are served by the real repo, so entity
  hydration and history still work. Writes fail the way Ecto itself fails a
  write: `insert/1,2` returns `{:error, changeset}` with an invalid changeset
  carrying `action: :insert`, `insert!/1,2` raises
  `Ecto.InvalidChangesetError`, and `transaction/1,2` over an `Ecto.Multi`
  reports the failing insert operation as `{:error, name, changeset, %{}}`.
  A `transaction/1,2` given a function runs against the real repo, so a
  function that calls back into this module still observes the failing write
  and `rollback/1` behaves normally.
  """

  def all(queryable), do: StateMachine.Repo.all(queryable)
  def all(queryable, opts), do: StateMachine.Repo.all(queryable, opts)

  def one(queryable), do: StateMachine.Repo.one(queryable)
  def one(queryable, opts), do: StateMachine.Repo.one(queryable, opts)

  def rollback(value), do: StateMachine.Repo.rollback(value)

  def insert(struct_or_changeset, _opts \\ []) do
    {:error, failed_changeset(struct_or_changeset)}
  end

  def insert!(struct_or_changeset, _opts \\ []) do
    raise Ecto.InvalidChangesetError,
      action: :insert,
      changeset: failed_changeset(struct_or_changeset)
  end

  def transaction(multi_or_fun, opts \\ [])

  def transaction(%Ecto.Multi{} = multi, _opts) do
    {name, changeset} = failing_operation(multi)
    {:error, name, changeset, %{}}
  end

  def transaction(fun, opts) when is_function(fun) do
    StateMachine.Repo.transaction(fun, opts)
  end

  defp failing_operation(multi) do
    Enum.find_value(Ecto.Multi.to_list(multi), {:insert, failed_changeset()}, fn
      {name, {:changeset, %Ecto.Changeset{} = changeset, _op_opts}} ->
        {name, failed_changeset(changeset)}

      {name, {:insert, %Ecto.Changeset{} = changeset, _op_opts}} ->
        {name, failed_changeset(changeset)}

      _other ->
        nil
    end)
  end

  defp failed_changeset do
    {%{}, %{entity_id: :string}}
    |> Ecto.Changeset.cast(%{}, [:entity_id])
    |> failed_changeset()
  end

  defp failed_changeset(%Ecto.Changeset{} = changeset) do
    %{Ecto.Changeset.add_error(changeset, :entity_id, "is invalid") | action: :insert}
  end

  defp failed_changeset(struct) do
    struct
    |> Ecto.Changeset.change()
    |> failed_changeset()
  end
end

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

  # ---------------------------------------------------------------------------
  # DB write failures
  # ---------------------------------------------------------------------------

  test "transition/3 reports a failed DB write as {:error, {:db_error, reason}}" do
    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    id = unique_entity_id("db-error")

    assert {:ok, :pending} = StateMachine.start(failing, id)

    assert {:error, {:db_error, _reason}} =
             StateMachine.transition(failing, id, :confirm)
  end

  test "a failed DB write leaves the in-memory state at its previous value", %{sm: sm} do
    id = unique_entity_id("db-error-state")

    # Persist a real :confirmed state first, so the failing server hydrates to
    # a non-initial state and any reset would be visible.
    {:ok, :pending} = StateMachine.start(sm, id)
    {:ok, :confirmed} = StateMachine.transition(sm, id, :confirm)

    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    assert {:ok, :confirmed} = StateMachine.start(failing, id)

    assert {:error, {:db_error, _reason}} = StateMachine.transition(failing, id, :ship)

    # The write failed, so :shipped must not have been applied in memory.
    assert {:ok, :confirmed} = StateMachine.get_state(failing, id)
  end

  test "invalid transitions are rejected before any DB write is attempted" do
    {:ok, failing} = StateMachine.start_link(repo: StateMachineTest.FailingInsertRepo)
    id = unique_entity_id("db-error-invalid")

    {:ok, :pending} = StateMachine.start(failing, id)

    # :ship is not valid from :pending and writes nothing, so a repo whose
    # every write fails cannot turn this into a :db_error.
    assert {:error, :invalid_transition} = StateMachine.transition(failing, id, :ship)
  end

  defp unique_entity_id(prefix) do
    "order:#{prefix}:#{System.pid()}:#{System.unique_integer([:positive])}"
  end
end
