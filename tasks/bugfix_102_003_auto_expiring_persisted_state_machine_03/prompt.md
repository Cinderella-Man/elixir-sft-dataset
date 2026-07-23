# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Design Brief: Auto-Expiring, Persisted Entity State Machine (Elixir)

## Problem

Stateful entities move through an order-processing lifecycle, and every transition they make must
be durably recorded so the current state can be rebuilt after a restart. Manual transitions alone
are not enough: an entity that is left sitting in the `:pending` state past a configured
time-to-live must be swept up by the server itself and moved to `:cancelled`, with that automatic
transition persisted exactly like a manual one.

Deliver an Elixir GenServer module called `StateMachine` that manages this lifecycle, persists
every state transition to a database, and adds **time-triggered automatic expiry**.

## Constraints

### The state machine definition

Use the following order-processing lifecycle:

States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`

Valid transitions (current_state + event → next_state):
  - :pending    + :confirm  → :confirmed
  - :confirmed  + :ship     → :shipped
  - :shipped    + :deliver  → :delivered
  - :pending    + :cancel   → :cancelled
  - :confirmed  + :cancel   → :cancelled
  - :pending    + :expire   → :cancelled

Any other (state, event) combination is invalid.

### Automatic expiry

- `start_link/1` accepts an optional `:pending_ttl_ms` option (a non-negative integer number of
  milliseconds). If it is **not** supplied (or is `nil`), automatic expiry is disabled.

- When `start/2` loads or seeds an entity whose current state is `:pending` **and** a
  `:pending_ttl_ms` was configured, the server schedules an expiry check that fires after
  `:pending_ttl_ms` milliseconds.

- When that check fires: if the entity is **still** `:pending`, the server applies the `:expire`
  event, transitioning `:pending → :cancelled`, persisting a transition row with event
  `"expire"`, and updating in-memory state. If the entity is no longer `:pending` (because it was
  confirmed, cancelled, etc. in the meantime), the check does nothing and writes nothing.

### Persistence

Use Ecto. Assume the caller supplies a configured Ecto repo. The relevant table is
`entity_transitions` with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `inserted_at` — utc_datetime_usec, non-null

The GenServer keeps an in-memory map of `%{entity_id => current_state}` as its state. On
`start/2`, it queries the DB for the most recent `to_state` for that entity. On restart, the
in-memory map is empty, so the next `start/2` call re-hydrates from the DB — including entities
that were automatically expired.

### Concurrency

`transition/3` must be implemented as a `call` (not a cast) so that concurrent callers serialize
through the GenServer and there are no race conditions. The automatic expiry check must run inside
the server process as well, so it serializes against manual transitions: whichever happens first
wins, and the other becomes a no-op or an `:invalid_transition`.

### Error handling

- DB write failures in `transition/3` should return `{:error, {:db_error, reason}}` and must NOT
  update the in-memory state.

### Dependencies

Use only Ecto (plus its adapters) as the external dependency — no additional libraries.

### Repo and migration contract

- Define the repo module yourself, named exactly `StateMachine.Repo`, as a bare
  `use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3` — but do NOT
  configure or start it: the test environment supplies its configuration (SQLite database
  path, sandbox pool) and starts it before your GenServer runs, injecting it via the
  `repo:` option. The tests run the migration themselves by module name, so no
  `priv/repo/migrations/` file is needed — but the migration module must be named exactly
  `Repo.Migrations.CreateEntityTransitions` and written as a `change/0` migration valid for
  SQLite (plain `Ecto.Migration`, no database-specific SQL).

## Required public interface

1. `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto repo
   module), an optional `:pending_ttl_ms` option (see above), and an optional `:name` option for
   process registration.

2. `StateMachine.start(server, entity_id)` — loads the latest persisted state for the given entity
   from the database. If no record exists, the entity starts in the `:pending` state. Returns
   `{:ok, current_state}`. (This is also the point at which an expiry check is scheduled for a
   pending entity when a TTL is configured.)

3. `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state}` for a previously
   started entity, or `{:error, :not_found}` if the entity has never been started in this session.

4. `StateMachine.transition(server, entity_id, event)` — attempts to transition the entity.
   - If valid: persists the new state + event to the DB, updates in-memory state, returns
     `{:ok, new_state}`.
   - If the (state, event) pair is not valid: returns `{:error, :invalid_transition}` and writes
     nothing.
   - If the entity has not been started yet: returns `{:error, :not_found}`.

5. `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every recorded
   transition for that entity in chronological (insertion) order. Each entry is a map with keys
   `:event`, `:from_state`, `:to_state`, and `:inserted_at`. The `:event`, `:from_state` and
   `:to_state` values are **atoms** in every returned entry — the string column values are
   deserialised back on read — while `:inserted_at` stays a `DateTime`.

## Acceptance criteria

The submission is accepted when it provides, as all three modules/files in clearly separated
blocks:

  1. The `EntityTransition` Ecto schema module.
  2. An Ecto migration file that creates the table.
  3. The `StateMachine` GenServer module.

…and every constraint above holds: the lifecycle and its valid transitions behave as specified
with all other (state, event) combinations rejected; automatic expiry activates only when
`:pending_ttl_ms` is configured, fires after the configured milliseconds, and is a no-op that
writes nothing when the entity has left `:pending`; the public interface returns exactly the
values listed; transitions and expiry checks serialize inside the server process; DB write
failures surface as `{:error, {:db_error, reason}}` with in-memory state untouched; and the repo
and migration modules match the naming and shape required by the test environment.

## The buggy module

```elixir
defmodule EntityTransition do
  @moduledoc """
  Ecto schema for a single persisted state-machine transition.

  Each row records that an entity moved `from_state -> to_state` in response to
  `event`, together with the UTC timestamp at which the transition was written.
  All lifecycle values are stored as strings (the atom serialised via
  `Atom.to_string/1`).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:inserted_at, :utc_datetime_usec)
  end
end

defmodule Repo.Migrations.CreateEntityTransitions do
  @moduledoc """
  Migration that creates the `entity_transitions` table used by `StateMachine`.

  Written with plain `Ecto.Migration` primitives so it is valid on any adapter
  (including SQLite): no database-specific SQL is used.
  """

  use Ecto.Migration

  @doc """
  Creates the `entity_transitions` table and an index on `entity_id`.
  """
  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end
end

defmodule StateMachine.Repo do
  @moduledoc """
  Ecto repository used by `StateMachine` to persist entity transitions.

  The concrete database configuration (SQLite database path, pool, ...) is
  supplied by the host application environment; this module only wires the
  repository to the SQLite3 adapter. It exposes the standard `Ecto.Repo`
  callbacks (all generated by `use Ecto.Repo`).
  """

  use Ecto.Repo,
    otp_app: :state_machine,
    adapter: Ecto.Adapters.SQLite3
end

defmodule StateMachine do
  @moduledoc """
  GenServer that manages the lifecycle of stateful entities for an
  order-processing workflow, persisting every state transition to a database and
  supporting time-triggered automatic expiry of `:pending` entities.

  ## Lifecycle

  States: `:pending`, `:confirmed`, `:shipped`, `:delivered`, `:cancelled`.

  Valid transitions (`current_state + event -> next_state`):

    * `:pending`   + `:confirm` -> `:confirmed`
    * `:confirmed` + `:ship`    -> `:shipped`
    * `:shipped`   + `:deliver` -> `:delivered`
    * `:pending`   + `:cancel`  -> `:cancelled`
    * `:confirmed` + `:cancel`  -> `:cancelled`
    * `:pending`   + `:expire`  -> `:cancelled`

  Any other `(state, event)` combination is invalid.

  ## Automatic expiry

  When a `:pending_ttl_ms` option is configured and an entity is loaded/seeded in
  the `:pending` state, an expiry check is scheduled. If the entity is still
  `:pending` when the check fires, the server applies the `:expire` event,
  persisting the automatic transition exactly like a manual one. Both manual
  transitions and the expiry check run inside the server process, so they
  serialize against each other with no race conditions.

  The server keeps an in-memory map of `%{entity_id => current_state}`. On
  restart the map is empty, so the next `start/2` re-hydrates from the database.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  @type state ::
          :pending | :confirmed | :shipped | :delivered | :cancelled
  @type event :: :confirm | :ship | :deliver | :cancel | :expire

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled,
    {:pending, :expire} => :cancelled
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module.
    * `:pending_ttl_ms` (optional) — non-negative integer number of milliseconds
      after which a still-`:pending` entity is automatically expired. If omitted
      or `nil`, automatic expiry is disabled.
    * `:name` (optional) — a name under which to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Loads the latest persisted state for `entity_id` and tracks it in memory.

  If no record exists the entity starts in `:pending`. When a `:pending_ttl_ms`
  was configured and the loaded state is `:pending`, an expiry check is
  scheduled. Always returns `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, state()}
  def start(server, entity_id) do
    GenServer.call(server, {:start, entity_id})
  end

  @doc """
  Returns `{:ok, current_state}` for a previously started entity, or
  `{:error, :not_found}` if the entity has never been started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, state()} | {:error, :not_found}
  def get_state(server, entity_id) do
    GenServer.call(server, {:get_state, entity_id})
  end

  @doc """
  Attempts to transition `entity_id` via `event`.

  Returns `{:ok, new_state}` on a valid transition (persisting first),
  `{:error, :invalid_transition}` for an invalid `(state, event)` pair,
  `{:error, :not_found}` if the entity has not been started, or
  `{:error, {:db_error, reason}}` if persistence fails (in which case the
  in-memory state is left unchanged).
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end

  @doc """
  Returns `{:ok, list}` where `list` is every recorded transition for
  `entity_id` in chronological (insertion) order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`, and
  `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    ttl = Keyword.get(opts, :pending_ttl_ms)
    {:ok, %{repo: repo, ttl: ttl, states: %{}}}
  end

  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_state(state.repo, entity_id)
    maybe_schedule(current, entity_id, state.ttl)
    new_states = Map.put(state.states, entity_id, current)
    {:reply, {:ok, current}, %{state | states: new_states}}
  end

  def handle_call({:get_state, entity_id}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      {:ok, current} -> {:reply, {:ok, current}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:transition, entity_id, event}, _from, state) do
    case Map.fetch(state.states, entity_id) do
      :error -> {:reply, {:error, :not_found}, state}
      {:error, current} -> apply_transition(entity_id, current, event, state)
    end
  end

  def handle_call({:history, entity_id}, _from, state) do
    repo = state.repo

    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id],
        select: %{
          event: t.event,
          from_state: t.from_state,
          to_state: t.to_state,
          inserted_at: t.inserted_at
        }
      )

    rows = Enum.map(repo.all(query), &decode_history_row/1)
    {:reply, {:ok, rows}, state}
  end

  @impl true
  def handle_info({:check_expiry, entity_id}, state) do
    case Map.get(state.states, entity_id) do
      :pending ->
        case persist(state.repo, entity_id, :expire, :pending, :cancelled) do
          :ok ->
            new_states = Map.put(state.states, entity_id, :cancelled)
            {:noreply, %{state | states: new_states}}

          {:error, _reason} ->
            {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec apply_transition(String.t(), state(), event(), map()) ::
          {:reply, term(), map()}
  defp apply_transition(entity_id, current, event, state) do
    case Map.fetch(@transitions, {current, event}) do
      :error ->
        {:reply, {:error, :invalid_transition}, state}

      {:ok, next} ->
        case persist(state.repo, entity_id, event, current, next) do
          :ok ->
            new_states = Map.put(state.states, entity_id, next)
            {:reply, {:ok, next}, %{state | states: new_states}}

          {:error, reason} ->
            {:reply, {:error, {:db_error, reason}}, state}
        end
    end
  end

  @spec decode_history_row(map()) :: map()
  defp decode_history_row(row) do
    %{
      event: String.to_existing_atom(row.event),
      from_state: String.to_existing_atom(row.from_state),
      to_state: String.to_existing_atom(row.to_state),
      inserted_at: row.inserted_at
    }
  end

  @spec load_state(module(), String.t()) :: state()
  defp load_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state
      )

    case repo.one(query) do
      nil -> :pending
      to_state -> String.to_existing_atom(to_state)
    end
  end

  @spec maybe_schedule(state(), String.t(), non_neg_integer() | nil) :: :ok
  defp maybe_schedule(:pending, entity_id, ttl) when is_integer(ttl) do
    Process.send_after(self(), {:check_expiry, entity_id}, ttl)
    :ok
  end

  defp maybe_schedule(_state, _entity_id, _ttl), do: :ok

  @spec persist(module(), String.t(), event(), state(), state()) ::
          :ok | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    row = %EntityTransition{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    case repo.insert(row) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Failing test report

```
12 of 19 test(s) failed:

  * test full happy path: pending -> confirmed -> shipped -> delivered
      {:EXIT, #PID<0.255.0>}: {{:case_clause, {:ok, :pending}}, [{StateMachine, :handle_call, 3, [file: ~c".gen_staging/bugfix_102_003_auto_expiring_persisted_state_machine_03_mutant.ex", line: 215]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}

  * test invalid event returns :invalid_transition and does not change state
      {:EXIT, #PID<0.260.0>}: {{:case_clause, {:ok, :pending}}, [{StateMachine, :handle_call, 3, [file: ~c".gen_staging/bugfix_102_003_auto_expiring_persisted_state_machine_03_mutant.ex", line: 215]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}

  * test confirming before the TTL prevents auto-expiry
      {:EXIT, #PID<0.281.0>}: {{:case_clause, {:ok, :pending}}, [{StateMachine, :handle_call, 3, [file: ~c".gen_staging/bugfix_102_003_auto_expiring_persisted_state_machine_03_mutant.ex", line: 215]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}

  * test manual :expire from :pending is a valid transition
      {:EXIT, #PID<0.287.0>}: {{:case_clause, {:ok, :pending}}, [{StateMachine, :handle_call, 3, [file: ~c".gen_staging/bugfix_102_003_auto_expiring_persisted_state_machine_03_mutant.ex", line: 215]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}

  (…8 more)
```
