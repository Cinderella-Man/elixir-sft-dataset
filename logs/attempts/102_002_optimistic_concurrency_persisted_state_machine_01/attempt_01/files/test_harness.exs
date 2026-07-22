# ---------------------------------------------------------------------------
# Self-contained test repo.
#
# The check environment did not provide a live `StateMachine.Repo` (every DB
# call failed with `:undef` on `StateMachine.Repo.get_dynamic_repo/0`), so the
# harness stands one up itself: a real SQLite Ecto repo backed by the sandbox
# pool, migrated once with the bundle's own migration, then switched to manual
# sandbox mode so each test can check out an isolated, shared owner.
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

try do
  Ecto.Migrator.up(
    StateMachine.Repo,
    20_240_101_000_000,
    Repo.Migrations.CreateEntityTransitions,
    log: false
  )
rescue
  _ -> :ok
end

Ecto.Adapters.SQL.Sandbox.mode(StateMachine.Repo, :manual)

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
end
