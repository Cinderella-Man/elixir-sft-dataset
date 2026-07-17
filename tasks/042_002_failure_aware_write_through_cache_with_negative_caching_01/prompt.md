Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed write-through cache **and handles fallback failures explicitly with negative caching**.

Unlike a naive cache, the data source here can fail (the database is down, the row is being rebuilt, etc.). I want the cache to be *failure-aware*: successes are cached, and failures can be **negatively cached** for a bounded number of subsequent reads so a flapping backend does not get hammered — but the cache must eventually retry.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration, and a `:negative_hits` option (a non-negative integer, default `3`) that controls how many times a cached failure is served before it is evicted and the fallback is retried. It should own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)`. `fallback_fn` is a zero-arity function that returns either `{:ok, value}` or `{:error, reason}`.
  - On a **cache hit for a success**, return `{:ok, value}` (read directly from ETS, no GenServer round-trip).
  - On a **cache hit for a failure**, return `{:error, reason}` *without* calling the fallback, and count the serve toward the `:negative_hits` budget. Once the budget for that entry is exhausted, evict it so the next `fetch` retries the backend.
  - On a **cache miss**, call `fallback_fn.()` **at most once**. If it returns `{:ok, value}`, cache it permanently and return `{:ok, value}`. If it returns `{:error, reason}`, cache it negatively (subject to `:negative_hits`) and return `{:error, reason}`. When `:negative_hits` is `0`, failures are never cached.
- `CacheLayer.invalidate(server, table, key)` which removes the entry (success *or* failure) for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok`.

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. Success reads must be servable directly from ETS without a GenServer call; all writes, deletes, and negative-hit bookkeeping are serialised through the GenServer so `fallback_fn` runs at most once per miss even under concurrent access. The table-name → ETS-tid registry that powers the no-round-trip read path lives in `:persistent_term`, keyed `{CacheLayer, server_pid, table_name}`, and `terminate/2` must erase every entry the server put there so no stale keys survive shutdown.

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.