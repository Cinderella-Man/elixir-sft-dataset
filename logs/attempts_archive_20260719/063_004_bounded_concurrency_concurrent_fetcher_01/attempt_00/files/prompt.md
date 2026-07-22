# Bounded-Concurrency Concurrent Fetcher

Write me an Elixir module called `PooledFetcher` that fetches data from multiple sources concurrently but with a **bounded worker pool** — at most `max_concurrency` fetches may run at any instant, the rest wait in a queue — all under a single global timeout.

I need this function in the public API:

- `PooledFetcher.fetch_all(sources, max_concurrency, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, tuple, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `max_concurrency` is a positive integer — the maximum number of fetches allowed to run simultaneously.
  - `timeout_ms` is a single global wall-clock budget shared across the whole operation.

Behaviour:

- No more than `max_concurrency` fetches run at once. As each running fetch finishes, the next queued source is started, until all are done or the timeout fires.
- The timeout is a single global budget measured from the moment `fetch_all` is called — it is **not** reset per source and **not** reset when a queued source finally starts.
- The function returns a map of `%{name => result_tuple}` covering every source, where each value is one of:
  - `{:ok, value}` — the fetch completed successfully within the global timeout.
  - `{:error, reason}` — the fetch returned `{:error, reason}` or raised (crashes are captured).
  - `{:error, :timeout}` — the global timeout expired while this source was still **running or still waiting in the queue** (i.e. it never got a chance to finish).
- When the timeout fires, any still-running fetch processes must be killed immediately — no zombie processes left behind. The function returns only after all spawned processes are done or confirmed dead.
- If `sources` is empty, return `%{}` immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.). In particular, do not rely on `Task.async_stream/3`'s per-element timeout — the timeout here is global.

Give me the complete implementation in a single file with a single module.