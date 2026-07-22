# The generated harness references `StateMachine.Repo`, but the execution
# environment does not actually define or start that module (the failures were
# all `:undef` on `StateMachine.Repo.get_dynamic_repo/0`). To make the suite
# self-contained we define, start, and migrate a real SQLite-backed repo here —
# using the very same `Ecto.Adapters.SQL.Sandbox` the tests rely on — before any
# test runs. The `StateMachine` GenServer still receives it purely via `repo:`.
sqlite_repo_config = [
  database: Path.join(System.tmp_dir!(), "state_machine_test.sqlite3"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5
]

Application.put_env(:state_machine, StateMachine.Repo, sqlite_repo_config)

defmodule StateMachine.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3
end

# Start from a clean database file on every run.
_ = Ecto.Adapters.SQLite3.storage_down(sqlite_repo_config)
_ = Ecto.Adapters.SQLite3.storage_up(sqlite_repo_config)

{:ok, _repo_pid} = StateMachine.Repo.start_link()

# Migrations run in the sandbox's default (automatic) mode, so the table is
# created on the real underlying connection and is visible to every later
# checked-out sandbox connection.
Ecto.Migrator.run(
  StateMachine.Repo,
  [{0, Repo.Migrations.CreateEntityTransitions}],
  :up,
  all: true
)

Ecto.Adapters.SQL.Sandbox.mode(StateMachine.Repo, :manual)

defmodule StateMachineTest do
  use ExUnit.Case, async: false

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(StateMachine.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    # Default server uses the documented default of 2 required approvals.
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Starting entities
  # ---------------------------------------------------------------------------

  test "start/2 returns :draft with 0 approvals for a brand-new entity", %{sm: sm} do
    assert {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
  end

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "cr:nope")
  end

  # ---------------------------------------------------------------------------
  # Submit / approve threshold (default required_approvals: 2)
  # ---------------------------------------------------------------------------

  test "submit moves draft to in_review with count reset to 0", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    assert {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
  end

  test "approve stays in_review until the required count, then flips to approved", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)

    assert {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :approved, 2} = StateMachine.get_state(sm, "cr:1")
  end

  test "reject from in_review", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:2")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:2", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:2", :approve)
    assert {:ok, :rejected, 1} = StateMachine.transition(sm, "cr:2", :reject)
  end

  test "withdraw from draft and from in_review", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:3")
    assert {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:3", :withdraw)

    {:ok, :draft, 0} = StateMachine.start(sm, "cr:4")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:4", :submit)
    assert {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:4", :withdraw)
  end

  # ---------------------------------------------------------------------------
  # Configurable threshold
  # ---------------------------------------------------------------------------

  test "required_approvals option changes the threshold" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:t3")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:t3", :submit)

    assert {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:t3", :approve)
    assert {:ok, :in_review, 2} = StateMachine.transition(sm, "cr:t3", :approve)
    assert {:ok, :approved, 3} = StateMachine.transition(sm, "cr:t3", :approve)
  end

  # ---------------------------------------------------------------------------
  # Invalid transitions
  # ---------------------------------------------------------------------------

  test "approve from draft is invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, :draft, 0} = StateMachine.get_state(sm, "cr:1")
  end

  test "approved is terminal: further events are invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :submit)
  end

  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.transition(sm, "cr:unknown", :submit)
  end

  test "invalid transition writes nothing", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:error, :invalid_transition} = StateMachine.transition(sm, "cr:1", :approve)
    assert {:ok, []} = StateMachine.history(sm, "cr:1")
  end

  # ---------------------------------------------------------------------------
  # History
  # ---------------------------------------------------------------------------

  test "history records event, states, and approvals in order", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:1")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:1", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:1", :approve)
    {:ok, :approved, 2} = StateMachine.transition(sm, "cr:1", :approve)

    assert {:ok, [s, a1, a2]} = StateMachine.history(sm, "cr:1")

    assert s.event == :submit
    assert s.from_state == :draft
    assert s.to_state == :in_review
    assert s.approvals == 0

    assert a1.event == :approve
    assert a1.from_state == :in_review
    assert a1.to_state == :in_review
    assert a1.approvals == 1

    assert a2.event == :approve
    assert a2.from_state == :in_review
    assert a2.to_state == :approved
    assert a2.approvals == 2
  end

  test "history for unknown entity returns empty list", %{sm: sm} do
    assert {:ok, []} = StateMachine.history(sm, "cr:nobody")
  end

  # ---------------------------------------------------------------------------
  # Recovery re-hydrates the approval count
  # ---------------------------------------------------------------------------

  test "start/2 re-hydrates a mid-review approval count after restart" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:rehy")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:rehy", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:rehy", :approve)

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)

    assert {:ok, :in_review, 1} = StateMachine.start(sm2, "cr:rehy")
    assert {:ok, :in_review, 2} = StateMachine.transition(sm2, "cr:rehy", :approve)
    assert {:ok, :approved, 3} = StateMachine.transition(sm2, "cr:rehy", :approve)
  end

  # ---------------------------------------------------------------------------
  # Concurrency: increments serialize deterministically
  # ---------------------------------------------------------------------------

  test "concurrent approvals climb to the threshold exactly once" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:cc")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:cc", :submit)

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> StateMachine.transition(sm, "cr:cc", :approve) end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _, _}, &1))
    invalid = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # First 3 approvals succeed (reaching the threshold), the other 7 hit the
    # terminal :approved state and are invalid.
    assert length(oks) == 3
    assert length(invalid) == 7
    assert {:ok, :approved, 3} = StateMachine.get_state(sm, "cr:cc")
  end
end
