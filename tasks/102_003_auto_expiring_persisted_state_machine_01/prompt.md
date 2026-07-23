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
