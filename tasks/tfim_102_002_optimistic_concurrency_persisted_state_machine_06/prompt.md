# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records one successful transition of an entity: the event that was
  applied, the state it moved from, the state it moved to, the entity's version
  *after* the transition, and the timestamp at which it was inserted.

  The `entity_transitions` table uses an auto-incrementing bigint primary key and
  a manually-managed `inserted_at` column (no `updated_at`), so the schema
  declares `inserted_at` as a plain field rather than using `timestamps/1`.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:version, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration creating the `entity_transitions` table.

  The table stores the full transition history for every entity. `entity_id` is
  indexed because both history lookups and latest-state hydration query by it.
  Uses only portable `Ecto.Migration` primitives so it runs cleanly on SQLite.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and its `entity_id` index.
  """
  @spec change() :: :ok
  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:version, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine do
  @moduledoc """
  GenServer managing the lifecycle of stateful order-processing entities with
  optimistic concurrency control.

  Every entity carries a monotonically increasing version number. A brand-new
  entity (with no persisted history) starts in the `:pending` state at version 0.
  Each successful transition increments the version by 1 and persists the new
  state, event, and version to the database.

  A caller invoking `transition/4` must present the version it expects to be
  operating on. If that expected version does not match the entity's current
  version, the write is rejected as stale and nothing is persisted. Because the
  version is checked inside `handle_call`, concurrent callers racing to apply the
  same event at the same expected version serialize through the GenServer: exactly
  one succeeds and the rest observe the incremented version and receive
  `{:error, {:stale_version, current_version}}`.

  The GenServer holds an in-memory map of
  `%{entity_id => {current_state, current_version}}`. On restart this map is empty,
  so the next `start/2` call re-hydrates the entity from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @typedoc "A valid state in the order-processing lifecycle."
  @type state_name :: :pending | :confirmed | :shipped | :delivered | :cancelled

  @typedoc "An event that may drive a transition."
  @type event :: :confirm | :ship | :deliver | :cancel

  @initial_state :pending

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the state-machine GenServer.

  Accepts a required `:repo` option (an Ecto repo module) and an optional `:name`
  option for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Loads the latest persisted state and version for `entity_id` from the database.

  If no record exists, the entity starts in the `:pending` state at version 0.
  Returns `{:ok, current_state, current_version}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state_name(), non_neg_integer()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state, current_version}` for a previously started entity,
  or `{:error, :not_found}` if the entity has never been started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state_name(), non_neg_integer()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`, given `expected_version`.

  Checks are applied in order: not-started, stale-version, invalid-transition,
  then the successful transition. On success persists the new state, event, and
  version, updates in-memory state, and returns `{:ok, new_state, new_version}`.
  """
  @spec transition(GenServer.server(), String.t(), event(), non_neg_integer()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :not_found}
          | {:error, {:stale_version, non_neg_integer()}}
          | {:error, :invalid_transition}
          | {:error, {:db_error, term()}}
  def transition(server, entity_id, event, expected_version) do
    GenServer.call(server, {:transition, entity_id, event, expected_version})
  end

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological (insertion) order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`, `:version`,
  and `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, %{repo: repo, entities: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    {cur_state, cur_version} = load_latest(state.repo, entity_id)
    entities = Map.put(state.entities, entity_id, {cur_state, cur_version})
    {:reply, {:ok, cur_state, cur_version}, %{state | entities: entities}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      {:ok, {cur_state, cur_version}} ->
        {:reply, {:ok, cur_state, cur_version}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event, expected_version}, _from, state) do
    case Map.fetch(state.entities, entity_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, {cur_state, cur_version}} ->
        do_transition(state, entity_id, event, expected_version, cur_state, cur_version)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    rows = load_history(state.repo, entity_id)
    {:reply, {:ok, rows}, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec do_transition(
          map(),
          String.t(),
          event(),
          non_neg_integer(),
          state_name(),
          non_neg_integer()
        ) :: {:reply, term(), map()}
  defp do_transition(state, entity_id, event, expected_version, cur_state, cur_version) do
    cond do
      expected_version != cur_version ->
        {:reply, {:error, {:stale_version, cur_version}}, state}

      not Map.has_key?(@transitions, {cur_state, event}) ->
        {:reply, {:error, :invalid_transition}, state}

      true ->
        next_state = Map.fetch!(@transitions, {cur_state, event})
        new_version = cur_version + 1
        commit(state, entity_id, event, cur_state, next_state, new_version)
    end
  end

  @spec commit(map(), String.t(), event(), state_name(), state_name(), non_neg_integer()) ::
          {:reply, term(), map()}
  defp commit(state, entity_id, event, from_state, to_state, new_version) do
    case persist(state.repo, entity_id, event, from_state, to_state, new_version) do
      {:ok, _record} ->
        entities = Map.put(state.entities, entity_id, {to_state, new_version})
        {:reply, {:ok, to_state, new_version}, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  @spec persist(module(), String.t(), event(), state_name(), state_name(), non_neg_integer()) ::
          {:ok, EntityTransition.t()} | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state, version) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      version: version,
      inserted_at: DateTime.utc_now()
    }

    %EntityTransition{}
    |> Ecto.Changeset.change(attrs)
    |> repo.insert()
  end

  @spec load_latest(module(), String.t()) :: {state_name(), non_neg_integer()}
  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.version, desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil ->
        {@initial_state, 0}

      %EntityTransition{to_state: to_state, version: version} ->
        {String.to_existing_atom(to_state), version}
    end
  end

  @spec load_history(module(), String.t()) :: [map()]
  defp load_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    query
    |> repo.all()
    |> Enum.map(fn t ->
      %{
        event: String.to_existing_atom(t.event),
        from_state: String.to_existing_atom(t.from_state),
        to_state: String.to_existing_atom(t.to_state),
        version: t.version,
        inserted_at: t.inserted_at
      }
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
```
