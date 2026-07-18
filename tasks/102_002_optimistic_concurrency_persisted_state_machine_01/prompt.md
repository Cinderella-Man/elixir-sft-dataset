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
  `:event`, `:from_state`, `:to_state`, `:version`, and `:inserted_at`. The `:event`,
  `:from_state`, and `:to_state` values are returned as **atoms** (converted back from the
  strings stored in the DB), `:version` is an integer, and `:inserted_at` is the stored
  timestamp. An entity with no recorded transitions (including one that has never been started
  in this session) returns `{:ok, []}`.

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
  `Ecto.Migration`, no database-specific SQL). The migration module must be named exactly
  `Repo.Migrations.CreateEntityTransitions` and written as a `change/0` migration — the test
  suite loads and runs it by that exact name.
