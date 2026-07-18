# Quorum First-N Concurrent Fetcher

Write me an Elixir module called `QuorumFetcher` that races data fetches from multiple sources concurrently and returns **as soon as a quorum of successes is reached**, cancelling everything still in flight.

I need this function in the public API:

- `QuorumFetcher.fetch_first(sources, count, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, tuple, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `count` is the number of **successful** fetches required (the quorum).
  - `timeout_ms` is a single global wall-clock budget shared across every fetch.

All fetches begin concurrently the moment `fetch_first` is called. The function returns a map of `%{name => result_tuple}` covering **every** source, where each value is one of:

- `{:ok, value}` — this fetch completed successfully (winners plus any source that had already succeeded).
- `{:error, reason}` — this fetch returned `{:error, reason}` or raised (crashes are captured, never counted as a success).
- `{:error, :cancelled}` — the quorum was reached and this source was still running, so it was cancelled.
- `{:error, :timeout}` — the global timeout expired before the quorum could be reached and this source had not finished.

Semantics:

- The function returns the instant the `count`-th success arrives; it must not wait for slower sources.
- When the quorum is reached, any still-running fetch processes must be killed immediately — no zombies. Still-running sources are reported as `{:error, :cancelled}`.
- If the quorum can never be met before the timeout, sources that finished are reported with their real outcome (`{:ok, …}` or `{:error, reason}`) and unfinished sources become `{:error, :timeout}`.
- If `sources` is empty, return `%{}` immediately.
- If `count <= 0`, the quorum is trivially satisfied: nothing is run and every source is reported as `{:error, :cancelled}`.
- The function returns only after every spawned process is done or confirmed dead.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.