Hey — I need you to build out a piece of our change-request review system, and I'd rather describe it than write a spec, so bear with me.

What I'm after is an Elixir GenServer module called `StateMachine` that manages the lifecycle of stateful entities, persists every state transition to a database, and drives a multi-approval workflow: the `:approve` event carries a persisted approval counter, and the entity only advances to `:approved` once a configured number of approvals has been reached.

The lifecycle I want modelled is our change-request review flow. The states are `:draft`, `:in_review`, `:approved`, `:rejected`, `:withdrawn`, and on top of the state each entity also carries a non-negative integer approval count. The transitions (current_state + event → next_state), along with what each does to the approval count, are:

  - :draft      + :submit   → :in_review   (approval count reset to 0)
  - :in_review  + :approve  → depends on the count (I'll explain below)
  - :in_review  + :reject   → :rejected    (approval count unchanged)
  - :draft      + :withdraw → :withdrawn   (approval count unchanged)
  - :in_review  + :withdraw → :withdrawn   (approval count unchanged)

Any other (state, event) combination is invalid — I don't want any of them quietly succeeding.

Now the interesting one. `:approve` is only valid from `:in_review`. Applying it increments the approval count by 1, and then it splits two ways. If the new count is less than the configured required number of approvals, the entity stays in `:in_review` — but I still want a transition row recorded for it, with `from_state` and `to_state` both `:in_review` and the new count. If the new count is greater than or equal to the required number of approvals, the entity transitions to `:approved` with that count. The required number of approvals is configured on the server; see what I want out of `start_link/1` below.

For the public API, here's what I need to be able to call:

  - `StateMachine.start_link(opts)` — starts the GenServer. It should accept a `:repo` option (an Ecto repo module), an optional `:required_approvals` option (a positive integer, and I want it to default to 2 when it isn't supplied), and an optional `:name` option for process registration.

  - `StateMachine.start(server, entity_id)` — loads the latest persisted state and approval count for the given entity out of the database. If there's no record at all, the entity starts in the `:draft` state with an approval count of 0. It returns `{:ok, current_state, approval_count}`.

  - `StateMachine.get_state(server, entity_id)` — returns `{:ok, current_state, approval_count}` for an entity that was previously started, or `{:error, :not_found}` if the entity has never been started in this session.

  - `StateMachine.transition(server, entity_id, event)` — attempts to apply `event`. When it's valid, it persists a transition row (new state + event + resulting approval count), updates the in-memory state, and returns `{:ok, new_state, new_approval_count}`. When the (state, event) pair isn't valid, it returns `{:error, :invalid_transition}` and writes nothing at all. And when the entity hasn't been started yet, it returns `{:error, :not_found}`.

  - `StateMachine.history(server, entity_id)` — returns `{:ok, list}`, where the list is every recorded transition for that entity in chronological (insertion) order. Each entry should be a map with the keys `:event`, `:from_state`, `:to_state`, `:approvals`, and `:inserted_at`. I want `:event`, `:from_state`, and `:to_state` to come back as atoms — the actual event/state atoms, not the strings they were persisted as — with `:approvals` being the integer count after that transition and `:inserted_at` being the stored timestamp. This one reads straight from the database and shouldn't require the entity to have been started; an entity with no recorded transitions just yields `{:ok, []}`.

Persistence goes through Ecto, and you can assume the caller hands us a configured Ecto repo. The table we care about is `entity_transitions`, with these columns:

  - `id` — bigint primary key (auto-increment)
  - `entity_id` — string, non-null, indexed
  - `event` — string (the atom serialised as a string), non-null
  - `from_state` — string, non-null
  - `to_state` — string, non-null
  - `approvals` — integer, non-null (the approval count *after* this transition)
  - `inserted_at` — utc_datetime_usec, non-null

So there are three things I need from you: the `EntityTransition` Ecto schema module, an Ecto migration file that creates the table, and the `StateMachine` GenServer module itself.

Internally, the GenServer should keep an in-memory map of `%{entity_id => {current_state, approval_count}}`. On `start/2` it queries the DB for the most recent row for that entity and derives both the current `to_state` and the current `approvals` value from it. That way, on restart the in-memory map is empty and the next `start/2` re-hydrates from the DB — including a partially-approved entity's mid-review count.

One thing I'm firm on for concurrency: `transition/3` has to be implemented as a `call`, not a cast, so concurrent callers serialize through the GenServer. Because the increment-and-check happens inside `handle_call`, a burst of concurrent `:approve` calls gets applied one at a time — the count climbs deterministically and the entity flips to `:approved` on exactly the call that reaches the required threshold, and any further `:approve` calls after that (coming from the terminal `:approved` state) are `:invalid_transition`.

On errors: if a DB write fails in `transition/3`, return `{:error, {:db_error, reason}}`, and make sure it does NOT update the in-memory state.

Please give me all three modules/files in clearly separated blocks, and stick to Ecto (plus its adapters) as the only external dependency — no additional libraries.

Last thing, about how this gets exercised on our side. The test environment provides a real, already-configured SQLite Ecto repo and injects it into your GenServer via the `repo:` option, so do NOT define a repo module or any repo configuration yourself. Your migration file has to live at a `priv/repo/migrations/<name>.exs` path: it gets executed against that repo before the tests run, so the schema/migration must be valid for SQLite — plain `Ecto.Migration`, no database-specific SQL. And the migration module must be named exactly `Repo.Migrations.CreateEntityTransitions` and written as a `change/0` migration, because the test suite loads and runs it by that exact name.
