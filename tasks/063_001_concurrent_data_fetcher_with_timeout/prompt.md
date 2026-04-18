Write me an Elixir module called `ConcurrentFetcher` that fetches data from multiple sources concurrently and enforces a global timeout across all of them.

I need this function in the public API:
- `ConcurrentFetcher.fetch_all(sources, timeout_ms)` where `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or raises/returns `{:error, reason}`. The function should return a map of `%{name => result_tuple}` where each value is one of:
  - `{:ok, value}` — the fetch completed successfully within the timeout
  - `{:error, :timeout}` — the global timeout expired before this fetch finished
  - `{:error, reason}` — the fetch function crashed or returned an error

The global timeout is shared across all sources, not per-source. Meaning if `timeout_ms` is 500 and one fetch takes 400ms and another takes 600ms, the first gets `{:ok, …}` and the second gets `{:error, :timeout}`. All fetches run concurrently from the moment `fetch_all` is called, not sequentially.

When the global timeout fires, any still-running fetch processes must be killed immediately — no zombies left behind. The function should return only after all spawned processes are either done or confirmed dead.

If `sources` is an empty list, return an empty map immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.