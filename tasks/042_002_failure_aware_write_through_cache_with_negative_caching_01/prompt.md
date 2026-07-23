# CacheLayer — failure-aware write-through ETS cache with negative caching

Implement an Elixir module `CacheLayer` that wraps database reads with an ETS-backed write-through cache and handles fallback failures explicitly via negative caching. Unlike a naive cache, the data source here can fail (the database is down, the row is being rebuilt, etc.). The cache must be *failure-aware*: successes are cached, and failures can be negatively cached for a bounded number of subsequent reads so a flapping backend does not get hammered — but the cache must eventually retry.

**Public API — `CacheLayer.start_link(opts)`**
- Starts the process as a GenServer.
- Accepts a `:name` option for process registration.
- Accepts a `:negative_hits` option — a non-negative integer, default `3` — controlling how many times a cached failure is served before it is evicted and the fallback is retried.
- Owns the lifecycle of all ETS tables it creates.

**Public API — `CacheLayer.fetch(server, table, key, fallback_fn)`**
- `fallback_fn` is a zero-arity function returning either `{:ok, value}` or `{:error, reason}`.
- Cache hit for a success: return `{:ok, value}`, read directly from ETS with no GenServer round-trip.
- Cache hit for a failure: return `{:error, reason}` *without* calling the fallback, and count the serve toward the `:negative_hits` budget. Once that entry's budget is exhausted, evict it so the next `fetch` retries the backend.
- Cache miss: call `fallback_fn.()` at most once.
  - `{:ok, value}` → cache permanently, return `{:ok, value}`.
  - `{:error, reason}` → cache negatively (subject to `:negative_hits`), return `{:error, reason}`.
  - When `:negative_hits` is `0`, failures are never cached.

**Public API — invalidation**
- `CacheLayer.invalidate(server, table, key)` removes the entry (success *or* failure) for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` removes **all** cached entries for the given `table`. Returns `:ok`.

**Storage and concurrency**
- Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use.
- Success reads must be servable directly from ETS without a GenServer call.
- All writes, deletes, and negative-hit bookkeeping are serialised through the GenServer, so `fallback_fn` runs at most once per miss even under concurrent access.
- The table-name → ETS-tid registry powering the no-round-trip read path lives in `:persistent_term`, keyed `{CacheLayer, server_pid, table_name}`.
- `terminate/2` must erase every entry the server put into `:persistent_term`, so no stale keys survive shutdown.

**Deliverable**
- Complete module in a single file.
- OTP and standard library only; no external dependencies.
