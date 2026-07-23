# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
<file path="priv/repo/migrations/YYYYMMDDHHMMSS_create_entity_transitions.exs">
defmodule Repo.Migrations.CreateEntityTransitions do
  use Ecto.Migration

  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
    create(index(:entity_transitions, [:entity_id, :inserted_at]))
  end
end
</file>

<file path="lib/entity_transition.ex">
defmodule EntityTransition do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persisted record of a single state-machine transition for one entity.

  Fields
  ------
  entity_id   – domain ID of the tracked entity
  event       – the triggering event atom serialised as a string ("confirm", …)
  from_state  – state before the transition ("pending", …)
  to_state    – state after the transition ("confirmed", …)
  inserted_at – microsecond-precision UTC timestamp, set by the repo on insert
  """

  # Suppress updated_at; we only need a single insertion timestamp.
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "entity_transitions" do
    field(:entity_id, :string)
    field(:event, :string)
    field(:from_state, :string)
    field(:to_state, :string)

    timestamps()
  end

  @required [:entity_id, :event, :from_state, :to_state]

  @doc "Validates and wraps insertion attrs in a changeset."
  def changeset(transition \\ %__MODULE__{}, attrs) do
    transition
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_length(:entity_id, min: 1)
  end
end
</file>

<file path="lib/state_machine.ex">
defmodule StateMachine do
  use GenServer
  require Logger

  import Ecto.Query, only: [from: 2]

  @moduledoc """
  GenServer that manages the in-memory lifecycle state of entities and
  durably persists every valid transition to an Ecto-backed database.

  ## State machine

      :pending    + :confirm  → :confirmed
      :confirmed  + :ship     → :shipped
      :shipped    + :deliver  → :delivered
      :pending    + :cancel   → :cancelled
      :confirmed  + :cancel   → :cancelled

  Any other (state, event) pair is rejected as `:invalid_transition`.

  ## Example

      {:ok, pid} = StateMachine.start_link(repo: MyRepo, name: :orders)

      {:ok, :pending}   = StateMachine.start(pid, "order-1")
      {:ok, :confirmed} = StateMachine.transition(pid, "order-1", :confirm)
      {:ok, :shipped}   = StateMachine.transition(pid, "order-1", :ship)
      {:ok, history}    = StateMachine.history(pid, "order-1")
  """

  # ---------------------------------------------------------------------------
  # Transition table — pure data, lookup is O(1) map fetch
  # ---------------------------------------------------------------------------

  @transitions %{
    {:pending, :confirm} => :confirmed,
    {:confirmed, :ship} => :shipped,
    {:shipped, :deliver} => :delivered,
    {:pending, :cancel} => :cancelled,
    {:confirmed, :cancel} => :cancelled
  }

  # All valid state atoms must exist at compile time for String.to_existing_atom/1
  # to be safe when deserialising DB rows.
  @states [:pending, :confirmed, :shipped, :delivered, :cancelled]
  @initial_state :pending

  # Ensure the compiler keeps the atoms alive.
  def __states__, do: @states

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the GenServer.

  Options
  - `:repo`  (required) – Ecto repo module, e.g. `MyApp.Repo`
  - `:name`  (optional) – forwarded to `GenServer.start_link/3`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, server_opts, name_opts)
  end

  @doc """
  Loads the latest persisted state for `entity_id` from the DB and caches it.
  Falls back to `:pending` when no record exists yet.
  Returns `{:ok, current_state}`.
  """
  @spec start(GenServer.server(), String.t()) :: {:ok, atom()}
  def start(server, entity_id),
    do: GenServer.call(server, {:start, entity_id})

  @doc """
  Returns `{:ok, current_state}` for a previously started entity, or
  `{:error, :not_found}` if the entity was never started in this session.
  """
  @spec get_state(GenServer.server(), String.t()) ::
          {:ok, atom()} | {:error, :not_found}
  def get_state(server, entity_id),
    do: GenServer.call(server, {:get_state, entity_id})

  @doc """
  Attempts to apply `event` to `entity_id`.

  - `{:ok, new_state}`              – transition valid; DB write succeeded.
  - `{:error, :invalid_transition}` – no matching (state, event) in the table; DB unchanged.
  - `{:error, :not_found}`          – entity not started in this session.
  - `{:error, {:db_error, reason}}` – Ecto write failed; in-memory state unchanged.
  """
  @spec transition(GenServer.server(), String.t(), atom()) ::
          {:ok, atom()}
          | {:error, :invalid_transition}
          | {:error, :not_found}
          | {:error, {:db_error, any()}}
  def transition(server, entity_id, event),
    do: GenServer.call(server, {:transition, entity_id, event})

  @doc """
  Returns `{:ok, list}` of every recorded transition for `entity_id` in
  chronological order. Each entry is:

      %{event: :confirm, from_state: :pending, to_state: :confirmed, inserted_at: ~U[…]}
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]} | {:error, any()}
  def history(server, entity_id),
    do: GenServer.call(server, {:history, entity_id})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    # in-memory map: %{ entity_id => current_state_atom }
    {:ok, %{repo: repo, entities: %{}}}
  end

  # :start — hydrate from DB (or seed with :pending), cache in map
  @impl true
  def handle_call({:start, entity_id}, _from, state) do
    current = load_latest_state(state.repo, entity_id)
    new_entities = Map.put(state.entities, entity_id, current)
    {:reply, {:ok, current}, %{state | entities: new_entities}}
  end

  # :get_state — pure in-memory lookup
  @impl true
  def handle_call({:get_state, entity_id}, _from, state) do
    reply =
      case Map.fetch(state.entities, entity_id) do
        {:ok, current} -> {:ok, current}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  # :transition — serialised call; in-memory update only after DB write succeeds
  @impl true
  def handle_call({:transition, entity_id, event}, _from, state) do
    with {:found, current} <- entity_lookup(state.entities, entity_id),
         {:valid, next_state} <- resolve_transition(current, event),
         {:persisted, _record} <- persist(state.repo, entity_id, event, current, next_state) do
      new_entities = Map.put(state.entities, entity_id, next_state)
      {:reply, {:ok, next_state}, %{state | entities: new_entities}}
    else
      {:not_found} -> {:reply, {:error, :not_found}, state}
      {:invalid} -> {:reply, {:error, :invalid_transition}, state}
      {:db_error, reason} -> {:reply, {:error, {:db_error, reason}}, state}
    end
  end

  # :history — fetch rows from DB, deserialise string columns back to atoms
  @impl true
  def handle_call({:history, entity_id}, _from, state) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.inserted_at]
      )

    result =
      try do
        rows = state.repo.all(query)

        history =
          Enum.map(rows, fn row ->
            %{
              event: String.to_existing_atom(row.event),
              from_state: String.to_existing_atom(row.from_state),
              to_state: String.to_existing_atom(row.to_state),
              inserted_at: row.inserted_at
            }
          end)

        {:ok, history}
      rescue
        e -> {:error, Exception.message(e)}
      end

    {:reply, result, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Fetches the most recent to_state for entity_id from the DB and converts
  # it from a string back to an atom. Returns @initial_state when no rows exist.
  #
  # Note: we deliberately avoid a `select:` clause and load full
  # %EntityTransition{} structs — pattern-matching on the whole struct keeps the
  # query portable across any injected repo implementation.
  @spec load_latest_state(module(), String.t()) :: atom()
  defp load_latest_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.inserted_at],
        limit: 1
      )

    case repo.one(query) do
      nil -> @initial_state
      record -> String.to_existing_atom(record.to_state)
    end
  end

  @spec entity_lookup(map(), String.t()) :: {:found, atom()} | {:not_found}
  defp entity_lookup(entities, entity_id) do
    case Map.fetch(entities, entity_id) do
      {:ok, state} -> {:found, state}
      :error -> {:not_found}
    end
  end

  @spec resolve_transition(atom(), atom()) :: {:valid, atom()} | {:invalid}
  defp resolve_transition(current_state, event) do
    case Map.fetch(@transitions, {current_state, event}) do
      {:ok, next} -> {:valid, next}
      :error -> {:invalid}
    end
  end

  # Inserts one row. Returns {:persisted, record} or {:db_error, reason}.
  # The caller must NOT update in-memory state on anything other than :persisted.
  @spec persist(module(), String.t(), atom(), atom(), atom()) ::
          {:persisted, EntityTransition.t()} | {:db_error, any()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state)
    }

    changeset = EntityTransition.changeset(attrs)

    try do
      case repo.insert(changeset) do
        {:ok, record} -> {:persisted, record}
        {:error, changeset} -> {:db_error, changeset}
      end
    rescue
      e ->
        Logger.error("[StateMachine] DB write failed: #{Exception.message(e)}")
        {:db_error, Exception.message(e)}
    end
  end
end
</file>
```

## New specification

Write me an Elixir GenServer module called `StateMachine` that manages the lifecycle of
stateful entities, persists every state transition to a database, and adds **time-triggered
automatic expiry**: an entity left in the `:pending` state for longer than a configured
time-to-live is automatically transitioned to `:cancelled` by the server, and that automatic
transition is persisted just like a manual one.

## State Machine Definition

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

## Automatic expiry

- `start_link/1` accepts an optional `:pending_ttl_ms` option (a non-negative integer number of
  milliseconds). If it is **not** supplied (or is `nil`), automatic expiry is disabled.

- When `start/2` loads or seeds an entity whose current state is `:pending` **and** a
  `:pending_ttl_ms` was configured, the server schedules an expiry check that fires after
  `:pending_ttl_ms` milliseconds.

- When that check fires: if the entity is **still** `:pending`, the server applies the `:expire`
  event, transitioning `:pending → :cancelled`, persisting a transition row with event
  `"expire"`, and updating in-memory state. If the entity is no longer `:pending` (because it was
  confirmed, cancelled, etc. in the meantime), the check does nothing and writes nothing.

## Public API

- `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto repo
  module), an optional `:pending_ttl_ms` option (see above), and an optional `:name` option for
  process registration.

- `StateMachine.start(server, entity_id)` — loads the latest persisted state for the given entity
  from the database. If no record exists, the entity starts in the `:pending` state. Returns
  `{:ok, current_state}`. (This is also the point at which an expiry check is scheduled for a
  pending entity when a TTL is configured.)

- `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state}` for a previously
  started entity, or `{:error, :not_found}` if the entity has never been started in this session.

- `StateMachine.transition(server, entity_id, event)` — attempts to transition the entity.
  - If valid: persists the new state + event to the DB, updates in-memory state, returns
    `{:ok, new_state}`.
  - If the (state, event) pair is not valid: returns `{:error, :invalid_transition}` and writes
    nothing.
  - If the entity has not been started yet: returns `{:error, :not_found}`.

- `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every recorded
  transition for that entity in chronological (insertion) order. Each entry is a map with keys
  `:event`, `:from_state`, `:to_state`, and `:inserted_at`. The `:event`, `:from_state` and
  `:to_state` values are **atoms** in every returned entry — the string column values are
  deserialised back on read — while `:inserted_at` stays a `DateTime`.

## Persistence

Use Ecto. Assume the caller supplies a configured Ecto repo. The relevant table is
`entity_transitions` with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `inserted_at` — utc_datetime_usec, non-null

Provide:
  1. The `EntityTransition` Ecto schema module.
  2. An Ecto migration file that creates the table.
  3. The `StateMachine` GenServer module.

The GenServer keeps an in-memory map of `%{entity_id => current_state}` as its state. On
`start/2`, it queries the DB for the most recent `to_state` for that entity. On restart, the
in-memory map is empty, so the next `start/2` call re-hydrates from the DB — including entities
that were automatically expired.

## Concurrency

`transition/3` must be implemented as a `call` (not a cast) so that concurrent callers serialize
through the GenServer and there are no race conditions. The automatic expiry check must run inside
the server process as well, so it serializes against manual transitions: whichever happens first
wins, and the other becomes a no-op or an `:invalid_transition`.

## Error Handling

- DB write failures in `transition/3` should return `{:error, {:db_error, reason}}` and must NOT
  update the in-memory state.

## Deliverables

Give me all three modules/files in clearly separated blocks. Use only Ecto (plus its adapters) as
the external dependency — no additional libraries.

## Additional interface contract

- Define the repo module yourself, named exactly `StateMachine.Repo`, as a bare
  `use Ecto.Repo, otp_app: :state_machine, adapter: Ecto.Adapters.SQLite3` — but do NOT
  configure or start it: the test environment supplies its configuration (SQLite database
  path, sandbox pool) and starts it before your GenServer runs, injecting it via the
  `repo:` option. The tests run the migration themselves by module name, so no
  `priv/repo/migrations/` file is needed — but the migration module must be named exactly
  `Repo.Migrations.CreateEntityTransitions` and written as a `change/0` migration valid for
  SQLite (plain `Ecto.Migration`, no database-specific SQL).
