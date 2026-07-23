# `CacheLayer` — ETS-backed read-through cache with single-flight, non-blocking loads

Implement an Elixir module `CacheLayer` that wraps database reads with an ETS-backed cache using a **single-flight (request-coalescing), non-blocking** concurrency model. Deliver the complete module in a single file.

**Concurrency model (the point of the ticket)**
- The naive design serialises *every* cache miss through the GenServer and runs the slow `fallback_fn` inside the GenServer's critical section, so one slow database call blocks misses for **all** keys. That is not acceptable here.
- The expensive `fallback_fn` must run **outside** the GenServer process, so a slow load for one key never blocks loads for other keys — distinct keys are computed concurrently.
- For a single key, when several callers miss at the same time, exactly **one** of them (the "leader") runs `fallback_fn`; the others ("followers") block until the leader finishes and then receive the leader's result.
- `fallback_fn` is called **at most once** per cache miss no matter how many callers race.
- If the leader crashes before producing a value, followers must not hang forever — one of them should get a chance to retry.

**Public API**
- `CacheLayer.start_link(opts)` — starts the process as a GenServer. Accepts a `:name` option for process registration. Owns the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` — returns `{:ok, value}`.
  - Cache hit: reads directly from ETS, no GenServer round-trip.
  - Cache miss: participates in the single-flight protocol above, returns `{:ok, value}`.
  - Any term `fallback_fn` produces — including `nil` — is stored and treated as a genuine cached value, so a later fetch of the same key is a hit that does not re-run `fallback_fn`.
- `CacheLayer.invalidate(server, table, key)` — removes the entry for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` — removes **all** cached entries for the given `table`. Returns `:ok`.

**Table management**
- Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer.
- Tables are created lazily on first use.

**GenServer responsibilities**
- Coordinates the single-flight bookkeeping: who is the leader for `{table, key}`, which callers are waiting.
- Must **not** execute `fallback_fn` itself.

**Table lookup and cleanup**
- Because cache hits bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call.
- If anything process-global is registered for that lookup (for example `:persistent_term` entries), the server must trap exits and its `terminate/2` must erase every such registration when it stops, so a cleanly stopped cache leaves nothing behind. The ETS tables themselves die with their owner.

**Constraints**
- Single file, complete module.
- OTP and the standard library only; no external dependencies.
