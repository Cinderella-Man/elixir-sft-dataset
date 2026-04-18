Write me an Elixir GenServer module called `RefreshAheadCache` that stores key-value pairs with a TTL and **proactively refreshes** entries approaching expiration, so under steady traffic cache reads never miss.

The motivation: a plain TTL cache has a "cliff" at expiration — the first read after a key expires has to recompute the value from scratch while the caller waits. For expensive computations behind a cache (DB queries, external API calls), that latency spike is visible to users and causes thundering-herd problems when many requests hit expired entries at once. Refresh-ahead avoids the cliff: when an entry passes a configurable threshold (e.g. 80% through its TTL), a background task is spawned to re-run the value's loader, and the new result replaces the old entry atomically. Reads during the refresh window continue to return the existing (still-fresh) value.

I need these functions in the public API:

- `RefreshAheadCache.start_link(opts)` to start the process. Options:
  - `:name` — optional process registration
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:sweep_interval_ms` — periodic hard-expiry sweep, milliseconds (default `60_000`); `:infinity` disables it
  - `:refresh_threshold` — a float in `(0.0, 1.0]` representing the fraction of the TTL after which a refresh is triggered (default `0.8`). At threshold `0.8` with a TTL of 1000ms, a read happening at `age >= 800ms` schedules a refresh.

- `RefreshAheadCache.put(server, key, value, ttl_ms, loader)` stores a key with its initial value, TTL, and a **loader function** — a zero-arity function that, when invoked, returns the next value to cache (possibly after a slow I/O call). The loader is stored alongside the value so the cache can call it again on refresh. If the key already exists, overwrite value, TTL, and loader. Returns `:ok`.

- `RefreshAheadCache.get(server, key)` retrieves a key. Behavior by state:
  - **Missing** — return `:miss`.
  - **Past hard expiry** (i.e. `now >= expires_at`) — delete the entry and return `:miss`. Lazy expiration on read, same as the original TTLCache.
  - **Past refresh threshold but not expired** — return `{:ok, value}` AND, if a refresh is not already in flight for this key, trigger one. The refresh runs asynchronously (see below). Reads continue returning the current value until the refresh completes.
  - **Below the refresh threshold** — return `{:ok, value}`, no refresh triggered.

- `RefreshAheadCache.delete(server, key)` removes a key. If a refresh is in flight for this key, the refresh's result (when it arrives) must be discarded — not applied to the cache, and not resurrected as a new entry. Returns `:ok` regardless.

- `RefreshAheadCache.stats(server)` returns `%{entries: non_neg_integer, refreshes_in_flight: non_neg_integer}` — useful for tests and observability.

**Async refresh machinery — the heart of this module:**

When `get/2` observes that an entry has crossed the refresh threshold and no refresh is already running for that key, the GenServer must:

1. Mark the key as "refresh in flight" in its state so concurrent reads don't trigger duplicate refreshes.
2. Spawn a `Task.start_link` (or equivalent) that:
   - Calls the loader function in the spawned process (NOT inside the GenServer, so the server isn't blocked on I/O).
   - When the loader returns a value, sends `{:refresh_complete, key, task_ref, new_value}` to the GenServer.
   - If the loader raises or throws, sends `{:refresh_failed, key, task_ref, reason}` instead.
3. Associate the spawned task with a unique `task_ref` (e.g. `make_ref()`) and store it in the in-flight map: `%{key => task_ref}`.

The GenServer then handles:

- `{:refresh_complete, key, task_ref, new_value}` — apply the new value ONLY IF the key still exists AND the `task_ref` matches the currently-tracked in-flight ref for that key. Otherwise discard (the key was deleted, overwritten, or another refresh started — the result is stale). On a matching apply, update value and `expires_at = now + original_ttl_ms`, preserve the original loader, and clear the in-flight entry.

- `{:refresh_failed, key, task_ref, reason}` — just clear the in-flight entry (same `task_ref` match check). The old value remains in place; the next `get` past threshold will trigger a new refresh attempt.

The **original TTL** is preserved across refreshes — refreshing restarts the clock to `now + ttl_ms_original`, not `now + some_new_ttl`. Each entry therefore remembers its configured `ttl_ms` in state.

**Hard-expiry sweep**: every `sweep_interval_ms`, scan all entries and remove those with `expires_at <= now`. Sweep must NOT cancel in-flight refresh tasks for entries that were just swept — the refresh result will simply be discarded when it arrives and doesn't match a live entry.

A key-race you must handle correctly: if the user `put`s a new value for a key that has a refresh in flight, the old refresh's result must be discarded on arrival. The trick is that `put` should update the in-flight map appropriately — concretely, the simplest correct behavior is that `put` clears the in-flight entry for that key (so when the old refresh arrives, its `task_ref` doesn't match and its result is discarded).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.