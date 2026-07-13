# Fix the failing module

I asked for the following:

Write me an Elixir GenServer module called `StateMachine` that manages the lifecycle of
stateful entities, persists every state transition to a database, and adds **optimistic
concurrency control**: every entity carries a monotonically increasing version number, and
each `transition` must present the version it expects to be operating on. A transition whose
expected version does not match the entity's current version is rejected as a stale write and
nothing is persisted.

## State Machine Definition

Use the following order-processing lifecycle:

States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`

Valid transitions (current_state + event → next_state):
  - :pending    + :confirm  → :confirmed
  - :confirmed  + :ship     → :shipped
  - :shipped    + :deliver  → :delivered
  - :pending    + :cancel   → :cancelled
  - :confirmed  + :cancel   → :cancelled

Any other (state, event) combination is invalid.

## Versioning

Every entity has a version number. A brand-new entity (no persisted history) starts in the
`:pending` state at **version 0**. Each successful transition increments the version by 1, so
after N successful transitions the entity is at version N. The version after a transition is
persisted alongside that transition.

## Public API

- `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto
  repo module) and an optional `:name` option for process registration.

- `StateMachine.start(server, entity_id)` — loads the latest persisted state **and version**
  for the given entity from the database. If no record exists, the entity starts in the
  `:pending` state at version 0. Returns `{:ok, current_state, current_version}`.

- `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state, current_version}`
  for a previously started entity, or `{:error, :not_found}` if the entity has never been
  started in this server session.

- `StateMachine.transition(server, entity_id, event, expected_version)` — attempts to
  transition the entity. The four checks are applied **in this exact order**:

  1. If the entity has not been started yet in this session: returns `{:error, :not_found}`
     and writes nothing.
  2. Otherwise, if `expected_version` does not equal the entity's current version: returns
     `{:error, {:stale_version, current_version}}` and writes nothing.
  3. Otherwise, if the (state, event) pair is not a valid transition: returns
     `{:error, :invalid_transition}` and writes nothing.
  4. Otherwise the transition is valid: persists the new state + event + new version to the DB,
     updates in-memory state, and returns `{:ok, new_state, new_version}` where
     `new_version == current_version + 1`.

  Note that the version check happens *before* the validity check, so a caller presenting a
  stale version always receives `{:error, {:stale_version, current_version}}` even if the event
  would also have been an invalid transition.

- `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every recorded
  transition for that entity in chronological (insertion) order. Each entry is a map with keys
  `:event`, `:from_state`, `:to_state`, `:version`, and `:inserted_at`.

## Persistence

Use Ecto. Assume the caller supplies a configured Ecto repo. The relevant table is
`entity_transitions` with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `version` — integer, non-null (the entity's version *after* this transition)
  - `inserted_at` — utc_datetime_usec, non-null

Provide:
  1. The `EntityTransition` Ecto schema module.
  2. An Ecto migration file that creates the table.
  3. The `StateMachine` GenServer module.

The GenServer keeps an in-memory map of `%{entity_id => {current_state, current_version}}` as
its state. On `start/2`, it queries the DB for the most recent row for that entity and derives
both the current `to_state` and the current version. On restart, the in-memory map is empty, so
the next `start/2` call re-hydrates from the DB.

## Concurrency

`transition/4` must be implemented as a `call` (not a cast) so that concurrent callers serialize
through the GenServer. Because the version is checked inside `handle_call`, when many callers
race to apply the same event at the same expected version, exactly one succeeds and every other
caller observes the now-incremented current version and receives
`{:error, {:stale_version, current_version}}`.

## Error Handling

- DB write failures in `transition/4` should return `{:error, {:db_error, reason}}` and must NOT
  update the in-memory state or version.

## Deliverables

Give me all three modules/files in clearly separated blocks. Use only Ecto (plus its adapters)
as the external dependency — no additional libraries.

## Additional interface contract

- The test environment provides a real, already-configured SQLite Ecto repo and injects it into
  your GenServer via the `repo:` option — do NOT define a repo module or any repo configuration.
  Your migration file must be at a `priv/repo/migrations/<name>.exs` path: it is executed against
  that repo before the tests run, so the schema/migration must be valid for SQLite (plain
  `Ecto.Migration`, no database-specific SQL).

Here is my current implementation, but it is failing tests:

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

The failure report:

```
Tests failed (13 failed, 0 errors):
  - test start/2 returns :pending at version 0 for a brand-new entity (StateMachineTest): {:EXIT, #PID<0.226.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test start/2 twice returns the same state and version (StateMachineTest): {:EXIT, #PID<0.231.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test get_state/2 reflects current state and version (StateMachineTest): {:EXIT, #PID<0.241.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test full happy path increments version each step (StateMachineTest): {:EXIT, #PID<0.246.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test cancellation from :pending and from :confirmed (StateMachineTest): {:EXIT, #PID<0.251.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test stale expected_version is rejected and writes nothing (StateMachineTest): {:EXIT, #PID<0.256.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test version check precedes validity check (StateMachineTest): {:EXIT, #PID<0.261.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test invalid event at the correct version returns :invalid_transition (StateMachineTest): {:EXIT, #PID<0.266.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test history/2 records event, states, and version in order (StateMachineTest): {:EXIT, #PID<0.276.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test history/2 for unknown entity returns empty list (StateMachineTest): {:EXIT, #PID<0.281.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"id\""}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {StateMachine, :load_history, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 294]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 206]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test start/2 re-hydrates state and version after restart (StateMachineTest): {:EXIT, #PID<0.286.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test concurrent transitions at the same expected version: one wins, rest are stale (StateMachineTest): {:EXIT, #PID<0.291.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test concurrent transitions on different entities all succeed (StateMachineTest): {:EXIT, #PID<0.296.0>}: {%Exqlite.Error{message: "no such table: entity_transitions", statement: "SELECT e0.\"id\", e0.\"entity_id\", e0.\"event\", e0.\"from_state\", e0.\"to_state\", e0.\"version\", e0.\"inserted_at\" FROM \"entity_transitions\" AS e0 WHERE (e0.\"entity_id\" = ?) ORDER BY e0.\"version\" DESC, e0.\"id\" DESC LIMIT 1"}, [{Ecto.Adapters.SQL, :raise_sql_call_error, 1, [file: ~c"lib/ecto/adapters/sql.ex", line: 1113, error_info: %{module: Exception}]}, {Ecto.Adapters.SQL, :execute, 6, [file: ~c"lib/ecto/adapters/sql.ex", line: 1011]}, {Ecto.Repo.Queryable, :execute, 4, [file: ~c"lib/ecto/repo/queryable.ex", line: 241]}, {Ecto.Repo.Queryable, :all, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 19]}, {Ecto.Repo.Queryable, :one, 3, [file: ~c"lib/ecto/repo/queryable.ex", line: 163]}, {StateMachine, :load_latest, 2, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 276]}, {StateMachine, :handle_call, 3, [file: ~c".gen_staging/102_002_optimistic_concurrency_persisted_state_machine_01/solution.ex", line: 180]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
```

Find the bug and give me the corrected complete module in a single file.
<!-- minted from logs/attempts/102_002_optimistic_concurrency_persisted_state_machine_01/attempt_1 -->
