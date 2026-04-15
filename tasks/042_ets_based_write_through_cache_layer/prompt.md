Write me an Elixir module called `CacheLayer` that wraps database reads with an ETS-backed write-through cache.

I need these functions in the public API:
- `CacheLayer.start_link(opts)` to start the process as a GenServer. It should accept a `:name` option for process registration and own the lifecycle of all ETS tables it creates.
- `CacheLayer.fetch(server, table, key, fallback_fn)` which returns the cached value for `{table, key}` if it exists in ETS, or calls `fallback_fn.()` on a cache miss, stores the result in ETS, and returns it. The return value should always be `{:ok, value}`.
- `CacheLayer.invalidate(server, table, key)` which removes the entry for `{table, key}` from the cache. Returns `:ok`.
- `CacheLayer.invalidate_all(server, table)` which removes **all** cached entries for the given `table`. Returns `:ok`.

Each `table` is an atom and should correspond to a separate ETS table owned by the GenServer. Tables should be created lazily on first use (i.e. create the ETS table the first time a given table atom is seen). Use `:set` type ETS tables with public read access so that `fetch` can read directly from ETS without going through the GenServer process, while writes and deletes are serialised through the GenServer.

The `fallback_fn` is a zero-arity anonymous function that the caller supplies. It will typically query a database. You must guarantee it is called **at most once** per cache miss — do not call it more than once even under concurrent access.

Give me the complete module in a single file. Use only OTP and the standard library, no external dependencies.