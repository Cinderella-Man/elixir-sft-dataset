# The generated harness references `StateMachine.Repo`, but the execution
# environment does not actually define or start that module (the failures were
# all `:undef` on `StateMachine.Repo.get_dynamic_repo/0`). To make the suite
# self-contained we define, start, and migrate a real SQLite-backed repo here —
# using the very same `Ecto.Adapters.SQL.Sandbox` the tests rely on — before any
# test runs. The `StateMachine` GenServer still receives it purely via `repo:`.
sqlite_repo_config = [
  # Unique per OS PROCESS: the validator runs one BEAM per task in parallel, so a
  # fixed filename means concurrent evals share one SQLite file and corrupt each
  # other. System.unique_integer alone is not enough (it is per-BEAM) — the pid
  # must be in the name too (same rule as EvalTask.Runner.uniq_suffix/0).
  database:
    Path.join(
      System.tmp_dir!(),
      "state_machine_test_#{System.pid()}_#{System.unique_integer([:positive])}.sqlite3"
    ),
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

# A repo whose writes always fail while its reads keep working against the real
# database. Injected through the documented `repo:` option, it lets the suite
# exercise the documented DB-write-failure contract of `transition/3` without
# touching the GenServer's internals.
defmodule FailingWriteRepo do
  @moduledoc false

  @failure :db_unavailable

  def insert(_struct_or_changeset, _opts \\ []), do: {:error, @failure}

  def insert!(_struct_or_changeset, _opts \\ []), do: raise("write failure")

  def one(queryable, opts \\ []), do: StateMachine.Repo.one(queryable, opts)

  def all(queryable, opts \\ []), do: StateMachine.Repo.all(queryable, opts)
end

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

  test "rejected and withdrawn are terminal and other bad pairs are invalid", %{sm: sm} do
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:inv1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :reject)
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:inv1", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :submit)
    {:ok, :rejected, 0} = StateMachine.transition(sm, "cr:inv1", :reject)

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :approve)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv1", :withdraw)
    assert {:ok, :rejected, 0} = StateMachine.get_state(sm, "cr:inv1")

    {:ok, :draft, 0} = StateMachine.start(sm, "cr:inv2")
    {:ok, :withdrawn, 0} = StateMachine.transition(sm, "cr:inv2", :withdraw)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv2", :submit)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "cr:inv2", :approve)
    assert {:ok, :withdrawn, 0} = StateMachine.get_state(sm, "cr:inv2")
  end

  test "start_link/1 registers the server under the given :name" do
    name = :"sm_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo, name: name)

    assert Process.whereis(name) == pid
    assert {:ok, :draft, 0} = StateMachine.start(name, "cr:named")
    assert {:ok, :in_review, 0} = StateMachine.transition(name, "cr:named", :submit)
    assert {:ok, :in_review, 0} = StateMachine.get_state(name, "cr:named")
  end

  test "withdraw from in_review keeps a non-zero approval count unchanged" do
    {:ok, sm} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(sm, "cr:wd")
    {:ok, :in_review, 0} = StateMachine.transition(sm, "cr:wd", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(sm, "cr:wd", :approve)
    {:ok, :in_review, 2} = StateMachine.transition(sm, "cr:wd", :approve)

    assert {:ok, :withdrawn, 2} = StateMachine.transition(sm, "cr:wd", :withdraw)
    assert {:ok, :withdrawn, 2} = StateMachine.get_state(sm, "cr:wd")

    assert {:ok, entries} = StateMachine.history(sm, "cr:wd")
    last = List.last(entries)
    assert last.event == :withdraw
    assert last.from_state == :in_review
    assert last.to_state == :withdrawn
    assert last.approvals == 2
  end

  # ---------------------------------------------------------------------------
  # DB write failures
  # ---------------------------------------------------------------------------

  test "a failed write reports {:db_error, reason} and leaves the entity in :draft" do
    {:ok, sm} = StateMachine.start_link(repo: FailingWriteRepo)
    assert {:ok, :draft, 0} = StateMachine.start(sm, "cr:dberr")

    assert {:error, {:db_error, _reason}} = StateMachine.transition(sm, "cr:dberr", :submit)

    # The server survives the failed write and the entity has not moved.
    assert {:ok, :draft, 0} = StateMachine.get_state(sm, "cr:dberr")
    assert {:ok, []} = StateMachine.history(sm, "cr:dberr")
  end

  test "a failed approve neither increments the count nor records a transition" do
    {:ok, healthy} = StateMachine.start_link(repo: StateMachine.Repo, required_approvals: 3)
    {:ok, :draft, 0} = StateMachine.start(healthy, "cr:dbapp")
    {:ok, :in_review, 0} = StateMachine.transition(healthy, "cr:dbapp", :submit)
    {:ok, :in_review, 1} = StateMachine.transition(healthy, "cr:dbapp", :approve)

    {:ok, broken} = StateMachine.start_link(repo: FailingWriteRepo, required_approvals: 3)
    assert {:ok, :in_review, 1} = StateMachine.start(broken, "cr:dbapp")
    assert {:error, {:db_error, _reason}} = StateMachine.transition(broken, "cr:dbapp", :approve)

    # Count is untouched in memory and nothing extra was persisted.
    assert {:ok, :in_review, 1} = StateMachine.get_state(broken, "cr:dbapp")
    assert {:ok, entries} = StateMachine.history(healthy, "cr:dbapp")
    assert length(entries) == 2
    assert List.last(entries).approvals == 1

    # The lost approval must still be needed: two more are required to approve.
    assert {:ok, :in_review, 2} = StateMachine.transition(healthy, "cr:dbapp", :approve)
    assert {:ok, :approved, 3} = StateMachine.transition(healthy, "cr:dbapp", :approve)
  end
end
