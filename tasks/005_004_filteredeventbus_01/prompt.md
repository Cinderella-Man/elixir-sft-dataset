Write me an Elixir GenServer module called `FilteredEventBus` that implements an in-process pub/sub event system where subscriptions carry **content-based filters** instead of wildcard topic matching.

The motivation: wildcard topic matching routes on a single string field. Content-based routing lets subscribers express interest in events by structural properties — "orders over $1000," "errors from region us-east," "any event where the user is an admin" — which topic wildcards can't express without explosive topic-name proliferation. This bus replaces wildcards entirely: every subscription uses a literal topic plus an optional filter.

The filter is expressed as a small **match-spec**-like DSL that the bus can evaluate on each event without `eval` or anonymous-function storage in state. The DSL supports exactly these clauses, combined implicitly as AND:

- `{:eq, path, value}` — event at `path` equals `value`
- `{:neq, path, value}` — event at `path` does not equal `value`
- `{:gt, path, value}` / `{:lt, path, value}` / `{:gte, path, value}` / `{:lte, path, value}` — numeric comparison; returns false if either side is non-numeric
- `{:in, path, list}` — event value at `path` is a member of `list`
- `{:exists, path}` — `path` resolves to a non-nil value
- `{:any, [filter, filter, ...]}` — at least one of the sub-filters matches (OR)
- `{:none, [filter, filter, ...]}` — none of the sub-filters match (NOT-OR, i.e. NAND of the disjunction)

A `path` is a list of map keys or integer list indices, e.g. `[:user, :role]` navigates `event[:user][:role]` for a map or `event.user.role` for a struct via `Access`. A path that doesn't resolve returns `nil` (never raises) and fails all clauses except `{:eq, path, nil}` and `{:neq, path, non_nil}`.

An entire subscription filter is a list of clauses, ALL of which must match (empty list = always match). This is different from `{:any, [...]}` which is OR within a nested group.

I need these functions in the public API:

- `FilteredEventBus.start_link(opts)` accepts `:name`.

- `FilteredEventBus.subscribe(server, topic, pid, filter \\ [])` subscribes `pid` to exact-matching `topic` with the given filter (a list of clauses). The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}` on success, `{:error, :invalid_filter}` if the filter fails structural validation.

- `FilteredEventBus.unsubscribe(server, topic, ref)` — removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.

- `FilteredEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every subscriber whose topic matches exactly AND whose filter matches the event. Returns `{:ok, matched_count}` giving the number of subscribers that received the event.

- `FilteredEventBus.test_filter(filter, event)` — a pure utility function (no GenServer) that returns `true` or `false` for a given filter and event, useful for subscribers that want to replicate the same filter logic client-side. Returns `{:error, :invalid_filter}` if the filter fails structural validation.

Filter validation at subscription time: recursively check that every clause matches one of the shapes above, that `path`s are lists of atoms/binaries/integers, and that `:any` / `:none` contain non-empty lists of valid sub-filters. Validation is structural only — it does NOT evaluate the filter; invalid path types raise no error, they just return `nil` during evaluation.

When a monitored subscriber dies (`:DOWN`), remove all its subscriptions across all topics.

A single pid may subscribe to the same topic multiple times with different filters and receives one delivery per matching subscription. Each subscription has its own ref and is independently unsubscribable.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.