# Fallback-Chain Concurrent Fetcher

Write me an Elixir module called `FallbackFetcher` that fetches data from multiple sources concurrently, where **each source carries an ordered chain of fallback functions** that are tried in sequence until one succeeds, all under a single global timeout.

I need this function in the public API:

- `FallbackFetcher.fetch_all(sources, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fns}` tuples. `name` can be any term (atom, string, tuple, etc.).
  - `fetch_fns` is a list of zero-arity functions (the fallback chain). Each function either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `timeout_ms` is a single global wall-clock budget shared across every source.

Behaviour:

- Every source runs **concurrently** with every other source, starting the moment `fetch_all` is called.
- **Within a single source**, the fallback functions are tried **sequentially, in order**: try the first; if it returns `{:ok, value}`, that source is done with `{:ok, value}`; if it returns `{:error, reason}` or raises, move on to the next function; continue until one succeeds or the chain is exhausted.
- The function returns a map of `%{name => result_tuple}` where each value is one of:
  - `{:ok, value}` — some fallback in the chain succeeded within the timeout.
  - `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons` is the list of failure reasons in the order the functions were tried (a raised exception is captured as its exception struct).
  - `{:error, :timeout}` — the global timeout expired while this source was still working through its chain.

Rules:

- The global timeout is shared across all sources, not per-source and not per-fallback. A source whose chain (summed sequentially) overruns the deadline is reported as `{:error, :timeout}`.
- When the timeout fires, any source still working must be killed immediately — no zombie processes. The function returns only after all spawned processes are done or confirmed dead.
- If `sources` is empty, return `%{}` immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.