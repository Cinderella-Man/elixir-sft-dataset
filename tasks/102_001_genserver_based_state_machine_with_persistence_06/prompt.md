# Implement the missing file

Below is the complete specification of a task, followed by its working,
fully tested multi-file solution — except that the entire content of
`lib/state_machine.ex` has been blanked to `# TODO`. Write that file so the whole
bundle passes the task's full test suite again. Change nothing else —
every other file must stay exactly as shown.

## The task

Write me an Elixir GenServer module called `StateMachine` that manages the lifecycle of
stateful entities, persists every state transition to a database, and recovers state on restart.

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

## Public API

- `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto
  repo module) and a `:name` option for process registration.

- `StateMachine.start(server, entity_id)` — loads the latest persisted state for the given
  entity from the database. If no record exists, the entity starts in the `:pending` state.
  Returns `{:ok, current_state}`.

- `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state}` for a
  previously started entity, or `{:error, :not_found}` if the entity has never been started
  in this server session.

- `StateMachine.transition(server, entity_id, event)` — attempts to transition the entity.
  - If valid: persists the new state + the event to the DB, updates in-memory state,
    returns `{:ok, new_state}`.
  - If the (state, event) pair is not a valid transition: returns
    `{:error, :invalid_transition}` and writes nothing to the DB.
  - If the entity has not been started yet: returns `{:error, :not_found}`.

- `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every
  recorded transition for that entity in chronological order. Each entry is a map with keys
  `:event`, `:from_state`, `:to_state`, and `:inserted_at`.

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

The GenServer must keep an in-memory map of `%{entity_id => current_state}` as its state.
On `start/2`, it queries the DB for the most recent `to_state` for that entity. On restart,
the in-memory map is empty, so the next `start/2` call re-hydrates from the DB.

## Concurrency

`transition/3` must be implemented as a `call` (not a cast) so that concurrent callers
serialize through the GenServer and there are no race conditions. The in-memory update and
the DB write must both happen inside the `handle_call` callback before the reply is sent.

## Error Handling

- DB write failures in `transition/3` should return `{:error, {:db_error, reason}}` and
  must NOT update the in-memory state.
- Use `Ecto.Multi` or a plain `Repo.insert` wrapped in a try/rescue; your choice.

## Deliverables

Give me all three modules/files in a single code block or clearly separated blocks. Use only
Ecto (plus its adapters) as the external dependency — no additional libraries.
## Additional interface contract

- The test environment provides a real, already-configured SQLite Ecto repo and injects it into your GenServer via the `repo:` option — do NOT define a repo module or any repo configuration. Your migration file must be at a `priv/repo/migrations/<name>.exs` path: it is executed against that repo before the tests run, so the schema/migration must be valid for SQLite (plain `Ecto.Migration`, no database-specific SQL).

## The bundle with `lib/state_machine.ex` missing

```elixir
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

# TODO
```

Give me only the complete content of `lib/state_machine.ex` — that one file, nothing
else.
