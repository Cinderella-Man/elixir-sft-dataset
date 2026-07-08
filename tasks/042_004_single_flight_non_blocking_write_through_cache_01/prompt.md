Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed cache using a **single-flight (request-coalescing), non-blocking** concurrency model.

The naive design serialises *every* cache miss through the GenServer and runs the slow `fallback_fn` inside the GenServer's critical section — so one slow database call blocks misses for **all** keys. I want a better concurrency model:

- The expensive `fallback_fn` must run **outside** the GenServer process, so a slow load for one key never blocks loads for other keys — distinct keys are computed concurrently.
- For a single key, if several callers miss at the same time, exactly **one** of them (the "leader") runs `fallback_fn`; the others ("followers") block until the leader finishes and then receive the leader's result. `fallback_fn` is called **at most once** per cache miss no matter how many callers race.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration and own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` which returns `{:ok, value}`. On a cache hit it reads directly from ETS (no GenServer round-trip). On a miss it participates in the single-flight protocol described above and returns `{:ok, value}`.
- `CacheLayer.invalidate(server, table, key)` which removes the entry for `{table, key}`. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok`.

Each `table` is an atom mapping to a separate `:set`, `:public` ETS table owned by the GenServer, created lazily on first use. The GenServer coordinates the single-flight bookkeeping (who is the leader for `{table, key}`, which callers are waiting) but must **not** execute `fallback_fn` itself. If the leader crashes before producing a value, the followers must not hang forever — one of them should get a chance to retry. Because cache hits bypass the GenServer, callers must be able to locate a table's ETS tid without a GenServer call; if you register anything process-global for that lookup (for example `:persistent_term` entries), the server must trap exits and its `terminate/2` must erase every such registration when it stops, so a cleanly stopped cache leaves nothing behind (the ETS tables themselves die with their owner).

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.