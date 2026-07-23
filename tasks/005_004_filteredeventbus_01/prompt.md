# `FilteredEventBus` — content-based pub/sub GenServer

Implement an Elixir GenServer module `FilteredEventBus`: an in-process pub/sub event system where subscriptions carry **content-based filters** instead of wildcard topic matching. Wildcards are replaced entirely — every subscription uses a literal topic plus an optional filter.

**Rationale (context, not a requirement):**
- Wildcard topic matching routes on a single string field.
- Content-based routing lets subscribers express interest by structural properties — "orders over $1000," "errors from region us-east," "any event where the user is an admin" — which topic wildcards can't express without explosive topic-name proliferation.

**Filter DSL:**
- A **match-spec**-like DSL the bus evaluates on each event, with no `eval` and no anonymous-function storage in state.
- Supports exactly these clauses, combined implicitly as AND:
  - `{:eq, path, value}` — event at `path` equals `value`.
  - `{:neq, path, value}` — event at `path` does not equal `value`.
  - `{:gt, path, value}` / `{:lt, path, value}` / `{:gte, path, value}` / `{:lte, path, value}` — numeric comparison; returns false if either side is non-numeric.
  - `{:in, path, list}` — event value at `path` is a member of `list`.
  - `{:exists, path}` — `path` resolves to a non-nil value.
  - `{:any, [clause, clause, ...]}` — at least one sub-clause matches (OR). Each element is a single clause tuple from this list; a nested clause-*list* (a whole filter) is **not** a valid element.
  - `{:none, [clause, clause, ...]}` — none of the sub-clauses match (NOT-OR, i.e. NAND of the disjunction). Elements are single clause tuples, exactly as for `:any`.

**Paths:**
- A `path` is a list of map keys or integer list indices; each element descends one level.
- A key looks up that key in a map (structs are navigated by key like maps); an integer selects the element at that 0-based index of a list.
- E.g. `[:user, :role]` navigates `event[:user][:role]`; `[:items, 0]` selects the first element of the list at `event[:items]`.
- A path that doesn't resolve returns `nil` (never raises) and fails all clauses except `{:eq, path, nil}` and `{:neq, path, non_nil}`.

**Filter semantics:**
- An entire subscription filter is a list of clauses, ALL of which must match (empty list = always match).
- This differs from `{:any, [...]}`, which is OR within a nested group of clauses.

**Public API:**
- `FilteredEventBus.start_link(opts)` — accepts `:name`.
- `FilteredEventBus.subscribe(server, topic, pid, filter \\ [])` — subscribes `pid` to exact-matching `topic` with the given filter (a list of clauses). Must `Process.monitor` the subscriber. Returns `{:ok, ref}` on success, `{:error, :invalid_filter}` if the filter fails structural validation.
- `FilteredEventBus.unsubscribe(server, topic, ref)` — removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.
- `FilteredEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every subscriber whose topic matches exactly AND whose filter matches the event. Returns `{:ok, matched_count}` — the number of subscribers that received the event.
- `FilteredEventBus.test_filter(filter, event)` — pure utility (no GenServer) returning `true` or `false` for a given filter and event, for subscribers replicating the same filter logic client-side. Returns `{:error, :invalid_filter}` if the filter fails structural validation.

**Filter validation (at subscription time):**
- Recursively check every clause matches one of the shapes above.
- `path`s must be lists of atoms/binaries/integers.
- `:any` / `:none` must contain non-empty lists of valid sub-clauses (bare clause tuples — a nested clause-list element makes the whole filter invalid).
- Validation is structural only — it does NOT evaluate the filter; invalid path types raise no error, they just return `nil` during evaluation.

**Lifecycle & delivery:**
- When a monitored subscriber dies (`:DOWN`), remove all its subscriptions across all topics.
- A single pid may subscribe to the same topic multiple times with different filters and receives one delivery per matching subscription.
- Each subscription has its own ref and is independently unsubscribable.

**Deliverable:**
- Complete module in a single file.
- Use only OTP standard library, no external dependencies.
