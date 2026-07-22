Write me an Elixir module called `Metrics` that collects **dimensional (labeled) metrics** using ETS for fast, concurrent-safe storage. Unlike a flat counter collector, each metric is identified by a name *plus a set of labels* (a map, e.g. `%{method: "GET", status: 200}`), so the same metric name can carry many independent label combinations — exactly like Prometheus time series.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It accepts a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, labels \\ %{}, amount \\ 1)` to atomically increment the counter for a specific `{name, labels}` series by `amount` (a non-negative integer). Use `:ets.update_counter` on the hot path — increments must NOT serialize through the GenServer. Two labels maps with the same key/value pairs in a different order (`%{a: 1, b: 2}` vs `%{b: 2, a: 1}`) refer to the *same* series. Support the natural call shapes: `increment(name)`, `increment(name, labels)`, `increment(name, amount)`, and `increment(name, labels, amount)`.
- `Metrics.gauge(name, value)` and `Metrics.gauge(name, labels, value)` to set the exact value of a series, overwriting the previous value.
- `Metrics.get(name, labels)` to return the current value of a specific series, or `nil` if that exact series does not exist.
- `Metrics.get(name)` to return the **aggregate** across all label combinations for that name (the sum of every series' value), or `nil` if the name has no series at all.
- `Metrics.series(name)` to return a list of `%{labels: labels_map, value: value}` — one entry per label combination recorded under `name`.
- `Metrics.reset(name, labels)` to set one specific series back to `0`, and `Metrics.reset(name)` to set *every* series under `name` back to `0`.
- `Metrics.all()` to return a map keyed by `{name, labels_map}` mapping to each series' value.

The ETS table must be public and named so `increment` can bypass the owning process. The GenServer exists only to own the table. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.