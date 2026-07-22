Write me an Elixir GenServer module called `StateMachine` that manages the lifecycle of
stateful entities, persists every state transition to a database, and drives a **multi-approval
workflow** in which the `:approve` event carries a persisted approval counter and only advances
the entity to `:approved` once a configured number of approvals has been reached.

## State Machine Definition

Use the following change-request review lifecycle:

States: `:draft`, `:in_review`, `:approved`, `:rejected`, `:withdrawn`

Each entity also carries a non-negative integer **approval count**.

Transitions (current_state + event → next_state), with their effect on the approval count:

  - :draft      + :submit   → :in_review   (approval count reset to 0)
  - :in_review  + :approve  → depends on the count (see below)
  - :in_review  + :reject   → :rejected    (approval count unchanged)
  - :draft      + :withdraw → :withdrawn   (approval count unchanged)
  - :in_review  + :withdraw → :withdrawn   (approval count unchanged)

Any other (state, event) combination is invalid.

### The `:approve` event

`:approve` is only valid from `:in_review`. Applying it **increments the approval count by 1**,
then:

  - If the new count is **less than** the configured required number of approvals, the entity
    **stays in** `:in_review` (a transition row is still recorded, with `from_state` and
    `to_state` both `:in_review` and the new count).
  - If the new count is **greater than or equal to** the required number of approvals, the entity
    transitions to `:approved` with that count.

The required number of approvals is configured on the server (see `start_link/1`).

## Public API

- `StateMachine.start_link(opts)` — starts the GenServer. Accepts a `:repo` option (an Ecto repo
  module), an optional `:required_approvals` option (a positive integer; **defaults to 2** when
  not supplied), and an optional `:name` option for process registration.

- `StateMachine.start(server, entity_id)` — loads the latest persisted state **and approval
  count** for the given entity from the database. If no record exists, the entity starts in the
  `:draft` state with an approval count of 0. Returns `{:ok, current_state, approval_count}`.

- `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state, approval_count}`
  for a previously started entity, or `{:error, :not_found}` if the entity has never been started
  in this session.

- `StateMachine.transition(server, entity_id, event)` — attempts to apply `event`.
  - If valid: persists a transition row (new state + event + resulting approval count), updates
    in-memory state, and returns `{:ok, new_state, new_approval_count}`.
  - If the (state, event) pair is not valid: returns `{:error, :invalid_transition}` and writes
    nothing.
  - If the entity has not been started yet: returns `{:error, :not_found}`.

- `StateMachine.history(server, entity_id)` — returns `{:ok, list}` where list is every recorded
  transition for that entity in chronological (insertion) order. Each entry is a map with keys
  `:event`, `:from_state`, `:to_state`, `:approvals`, and `:inserted_at`.

## Persistence

Use Ecto. Assume the caller supplies a configured Ecto repo. The relevant table is
`entity_transitions` with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `approvals` — integer, non-null (the approval count *after* this transition)
  - `inserted_at` — utc_datetime_usec, non-null

Provide:
  1. The `EntityTransition` Ecto schema module.
  2. An Ecto migration file that creates the table.
  3. The `StateMachine` GenServer module.

The GenServer keeps an in-memory map of `%{entity_id => {current_state, approval_count}}`. On
`start/2`, it queries the DB for the most recent row for that entity and derives both the current
`to_state` and the current `approvals` value. On restart, the in-memory map is empty, so the next
`start/2` re-hydrates from the DB — including a partially-approved entity's mid-review count.

## Concurrency

`transition/3` must be implemented as a `call` (not a cast) so that concurrent callers serialize
through the GenServer. Because the increment-and-check happens inside `handle_call`, a burst of
concurrent `:approve` calls is applied one at a time: the count climbs deterministically and the
entity flips to `:approved` on exactly the call that reaches the required threshold; any further
`:approve` calls after that (from the terminal `:approved` state) are `:invalid_transition`.

## Error Handling

- DB write failures in `transition/3` should return `{:error, {:db_error, reason}}` and must NOT
  update the in-memory state.

## Deliverables

Give me all three modules/files in clearly separated blocks. Use only Ecto (plus its adapters) as
the external dependency — no additional libraries.

## Additional interface contract

- The test environment provides a real, already-configured SQLite Ecto repo and injects it into
  your GenServer via the `repo:` option — do NOT define a repo module or any repo configuration.
  Your migration file must be at a `priv/repo/migrations/<name>.exs` path: it is executed against
  that repo before the tests run, so the schema/migration must be valid for SQLite (plain
  `Ecto.Migration`, no database-specific SQL).