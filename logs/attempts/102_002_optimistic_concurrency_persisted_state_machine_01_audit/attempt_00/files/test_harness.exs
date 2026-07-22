# ---------------------------------------------------------------------------
# Self-contained test repo.
#
# The check environment did not provide a live `StateMachine.Repo` (every DB
# call failed with `:undef` on `StateMachine.Repo.get_dynamic_repo/0`), so the
# harness stands one up itself: a real SQLite Ecto repo backed by the sandbox
# pool, its schema created once, then switched to manual sandbox mode so each
# test can check out an isolated, shared owner.
# ---------------------------------------------------------------------------

Application.put_env(:state_machine, StateMachine.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database:
    Path.join(System.tmp_dir!(), "state_machine_test_#{System.unique_integer([:positive])}.db"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1
)

unless Code.ensure_loaded?(StateMachine.Repo) do
  defmodule StateMachine.Repo do
    use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3
  end
end

_ = Application.ensure_all_started(:ecto_sql)
_ = Application.ensure_all_started(:ecto_sqlite3)

case StateMachine.Repo.start_link() do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(StateMachine.Repo, :auto)

# Create the schema directly (deterministically) instead of relying on the
# migrator, which was failing silently under the SQLite sandbox pool and left
# the `entity_transitions` table absent. This DDL is committed to the file DB
# while the sandbox is in :auto mode, so every later checked-out owner sees it.
Ecto.Adapters.SQL.query!(
  StateMachine.Repo,
  """
  CREATE TABLE IF NOT EXISTS entity_transitions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_id TEXT NOT NULL,
    event TEXT NOT NULL,
    from_state TEXT NOT NULL,
    to_state TEXT NOT NULL,
    version INTEGER NOT NULL,
    inserted_at TEXT NOT NULL
  )
  """,
  []
)

Ecto.Adapters.SQL.query!(
  StateMachine.Repo,
  """
  CREATE INDEX IF NOT EXISTS entity_transitions_entity_id_index
  ON entity_transitions (entity_id)
  """,
  []
)

Ecto.Adapters.SQL.Sandbox.mode(StateMachine.Repo, :manual)

# ---------------------------------------------------------------------------
# Dedicated repo for exercising the real migration's `change/0`.
#
# The main test flow builds its schema with raw DDL (for reliability under the
# sandbox pool), which never runs the migration module. To actually cover
# `Repo.Migrations.CreateEntityTransitions.change/0`, we stand up a second,
# non-sandboxed SQLite repo against a fresh file and run the migration through
# `Ecto.Migrator`. If `change/0` is gutted (e.g. replaced with a `raise`, or
# stripped of its `create table`/`create index` calls), the migration test below
# fails.
# ---------------------------------------------------------------------------

Application.put_env(:state_machine, StateMachine.MigrationRepo,
  adapter: Ecto.Adapters.SQLite3,
  database:
    Path.join(
      System.tmp_dir!(),
      # System.pid() as well: unique_integer is unique only WITHIN one BEAM, and
      # the validator runs one BEAM per task in parallel — two concurrent evals
      # could draw the same integer, share this file, and corrupt each other's
      # migration test (flaky 1/16 failures, 2026-07-13). Same rule as
      # EvalTask.Runner.uniq_suffix/0.
      "state_machine_migration_test_#{System.pid()}_#{System.unique_integer([:positive])}.db"
    ),
  pool_size: 1
)

unless Code.ensure_loaded?(StateMachine.MigrationRepo) do
  defmodule StateMachine.MigrationRepo do
    use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3
  end
end

case StateMachine.MigrationRepo.start_link() do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
end

defmodule StateMachineTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Real repo: the test environment provides StateMachine.Repo (SQLite),
  # already configured, with this bundle's migration applied.
  # ---------------------------------------------------------------------------

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(StateMachine.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Migration: change/0 must actually build the table and its index
  # ---------------------------------------------------------------------------

  test "migration change/0 builds a working entity_transitions table with its index" do
    # Runs the real migration module through the migrator against a fresh,
    # dedicated repo. A gutted change/0 (raise, or missing create table/index)
    # makes this fail.
    Ecto.Migrator.up(
      StateMachine.MigrationRepo,
      20_240_101_000_000,
      Repo.Migrations.CreateEntityTransitions,
      log: false
    )

    # The table exists and every declared column is usable.
    # The migration repo is NOT sandboxed (it is a real file, on purpose — see the
    # header), so a row written here can outlive the test and collide with a
    # concurrently-running eval of this same task. Key the row to this run.
    mid = "m:#{System.pid()}:#{System.unique_integer([:positive])}"

    StateMachine.MigrationRepo.query!(
      "INSERT INTO entity_transitions " <>
        "(entity_id, event, from_state, to_state, version, inserted_at) " <>
        "VALUES (?1, 'confirm', 'pending', 'confirmed', 1, '2026-01-01 00:00:00')",
      [mid]
    )

    %{rows: [[count]]} =
      StateMachine.MigrationRepo.query!(
        "SELECT count(*) FROM entity_transitions WHERE entity_id = ?1",
        [mid]
      )

    assert count == 1

    # The entity_id index the migration declares must also exist.
    %{rows: index_rows} =
      StateMachine.MigrationRepo.query!(
        "SELECT name FROM sqlite_master " <>
          "WHERE type = 'index' AND tbl_name = 'entity_transitions'",
        []
      )

    assert Enum.any?(index_rows, fn [name] ->
             name == "entity_transitions_entity_id_index"
           end)
  end

  # ---------------------------------------------------------------------------
  # Starting entities / versions
  # ---------------------------------------------------------------------------

  test "start/2 returns :pending at version 0 for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
  end

  test "start/2 twice returns the same state and version", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
  end

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "order:nope")
  end

  test "get_state/2 reflects current state and version", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Happy-path transitions increment the version
  # ---------------------------------------------------------------------------

  test "full happy path increments version each step", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")

    assert {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    assert {:ok, :shipped, 2} = StateMachine.transition(sm, "order:1", :ship, 1)
    assert {:ok, :delivered, 3} = StateMachine.transition(sm, "order:1", :deliver, 2)

    assert {:ok, :delivered, 3} = StateMachine.get_state(sm, "order:1")
  end

  test "cancellation from :pending and from :confirmed", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled, 1} = StateMachine.transition(sm, "order:2", :cancel, 0)

    {:ok, :pending, 0} = StateMachine.start(sm, "order:3")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:3", :confirm, 0)
    assert {:ok, :cancelled, 2} = StateMachine.transition(sm, "order:3", :cancel, 1)
  end

  # ---------------------------------------------------------------------------
  # Optimistic concurrency: stale version rejection
  # ---------------------------------------------------------------------------

  test "stale expected_version is rejected and writes nothing", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    # Present the old version 0 again
    assert {:error, {:stale_version, 1}} =
             StateMachine.transition(sm, "order:1", :ship, 0)

    # State/version unchanged, and no extra row written
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:1")
  end

  test "version check precedes validity check", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    # :deliver from :confirmed would be invalid, but the stale version wins
    assert {:error, {:stale_version, 1}} =
             StateMachine.transition(sm, "order:1", :deliver, 0)
  end

  test "invalid event at the correct version returns :invalid_transition", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver, 1)

    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:1")
  end

  test "transition on unknown entity returns :not_found (before version check)", %{sm: sm} do
    assert {:error, :not_found} =
             StateMachine.transition(sm, "order:unknown", :confirm, 0)
  end

  # ---------------------------------------------------------------------------
  # History
  # ---------------------------------------------------------------------------

  test "history/2 records event, states, and version in order", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:1", :confirm, 0)
    {:ok, :shipped, 2} = StateMachine.transition(sm, "order:1", :ship, 1)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")

    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed
    assert first.version == 1

    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
    assert second.version == 2
  end

  test "history/2 for unknown entity returns empty list", %{sm: sm} do
    assert {:ok, []} = StateMachine.history(sm, "order:nobody")
  end

  # ---------------------------------------------------------------------------
  # Recovery re-derives version from the DB
  # ---------------------------------------------------------------------------

  test "start/2 re-hydrates state and version after restart", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:99")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:99", :confirm, 0)
    {:ok, :shipped, 2} = StateMachine.transition(sm, "order:99", :ship, 1)

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    assert {:ok, :shipped, 2} = StateMachine.start(sm2, "order:99")
    assert {:ok, :delivered, 3} = StateMachine.transition(sm2, "order:99", :deliver, 2)
  end

  # ---------------------------------------------------------------------------
  # Concurrency: exactly one winner, the rest see a stale version
  # ---------------------------------------------------------------------------

  test "concurrent transitions at the same expected version: one wins, rest are stale", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:cc")

    tasks =
      for _ <- 1..20 do
        Task.async(fn -> StateMachine.transition(sm, "order:cc", :confirm, 0) end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, :confirmed, 1}, &1))
    stale = Enum.filter(results, &match?({:error, {:stale_version, 1}}, &1))

    assert length(oks) == 1
    assert length(stale) == 19
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm, "order:cc")
  end

  test "concurrent transitions on different entities all succeed", %{sm: sm} do
    for i <- 1..10, do: StateMachine.start(sm, "order:par:#{i}")

    tasks =
      for i <- 1..10 do
        Task.async(fn -> StateMachine.transition(sm, "order:par:#{i}", :confirm, 0) end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, &match?({:ok, :confirmed, 1}, &1))
  end

  test "transition/4 reports db errors and leaves in-memory state untouched" do
    defmodule StateMachineAuditFailingRepo do
      def one(_query), do: nil
      def all(_query), do: []
      def insert(_changeset), do: {:error, :disk_full}
    end

    {:ok, sm} = StateMachine.start_link(repo: StateMachineAuditFailingRepo)

    assert {:ok, :pending, 0} = StateMachine.start(sm, "order:dbfail")

    assert {:error, {:db_error, :disk_full}} =
             StateMachine.transition(sm, "order:dbfail", :confirm, 0)

    # Neither state nor version may move when the write failed.
    assert {:ok, :pending, 0} = StateMachine.get_state(sm, "order:dbfail")

    # A retry at the unchanged version must still be accepted as non-stale.
    assert {:error, {:db_error, :disk_full}} =
             StateMachine.transition(sm, "order:dbfail", :confirm, 0)

    GenServer.stop(sm)
  end

  test "history/2 entries carry an :inserted_at timestamp", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:ts")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:ts", :confirm, 0)

    assert {:ok, [entry]} = StateMachine.history(sm, "order:ts")
    assert Map.has_key?(entry, :inserted_at)
    assert %DateTime{} = entry.inserted_at
  end

  test "start_link/1 registers the process under the given :name option" do
    name = :"state_machine_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = StateMachine.start_link(repo: StateMachine.Repo, name: name)

    assert Process.whereis(name) == pid

    # The whole public API must be usable through the registered name.
    assert {:ok, :pending, 0} = StateMachine.start(name, "order:named")
    assert {:ok, :confirmed, 1} = StateMachine.transition(name, "order:named", :confirm, 0)
    assert {:ok, :confirmed, 1} = StateMachine.get_state(name, "order:named")

    GenServer.stop(name)
  end

  test "get_state/2 stays :not_found after restart until start/2 rehydrates", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:rehy")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:rehy", :confirm, 0)

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: StateMachine.Repo)

    # Persisted history alone must not make the entity "started" in the new session.
    assert {:error, :not_found} = StateMachine.get_state(sm2, "order:rehy")

    # not-started wins even when the presented version is the true current one.
    assert {:error, :not_found} = StateMachine.transition(sm2, "order:rehy", :ship, 1)

    assert {:ok, :confirmed, 1} = StateMachine.start(sm2, "order:rehy")
    assert {:ok, :confirmed, 1} = StateMachine.get_state(sm2, "order:rehy")

    GenServer.stop(sm2)
  end

  test "invalid transition at the current version persists no history row", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:inv")

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:inv", :ship, 0)

    assert {:ok, []} = StateMachine.history(sm, "order:inv")
    assert {:ok, :pending, 0} = StateMachine.get_state(sm, "order:inv")
  end

  test "terminal states and mismatched events are invalid transitions", %{sm: sm} do
    {:ok, :pending, 0} = StateMachine.start(sm, "order:term")
    {:ok, :confirmed, 1} = StateMachine.transition(sm, "order:term", :confirm, 0)
    {:ok, :shipped, 2} = StateMachine.transition(sm, "order:term", :ship, 1)

    # :cancel is only valid from :pending and :confirmed.
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:term", :cancel, 2)

    {:ok, :delivered, 3} = StateMachine.transition(sm, "order:term", :deliver, 2)
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:term", :cancel, 3)

    {:ok, :pending, 0} = StateMachine.start(sm, "order:term2")
    {:ok, :cancelled, 1} = StateMachine.transition(sm, "order:term2", :cancel, 0)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:term2", :confirm, 1)
  end
end
