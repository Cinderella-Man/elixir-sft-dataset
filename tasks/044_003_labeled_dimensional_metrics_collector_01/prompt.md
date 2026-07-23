Hey — I need you to write a module for us called `Metrics`, and I want to be specific about what it has to do because the flat counter collector we have today isn't cutting it.

The idea is **dimensional (labeled) metrics**, backed by ETS so storage is fast and concurrent-safe. Instead of a metric being identified by a name alone, each one is identified by a name *plus a set of labels* — a map, e.g. `%{method: "GET", status: 200}` — so a single metric name can carry many independent label combinations, exactly like Prometheus time series.

Here's the public API I'm asking for:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, labels \\ %{}, amount \\ 1)` to atomically increment the counter for a specific `{name, labels}` series by `amount` (a non-negative integer), creating the series (starting from `0`) if it doesn't exist yet. I want `:ets.update_counter` on the hot path — increments must NOT serialize through the GenServer. Two labels maps with the same key/value pairs in a different order (`%{a: 1, b: 2}` vs `%{b: 2, a: 1}`) have to refer to the *same* series. Please support the natural call shapes: `increment(name)`, `increment(name, labels)`, `increment(name, amount)`, and `increment(name, labels, amount)`. A negative `amount` must raise a `FunctionClauseError` (in both the `increment(name, amount)` and the `increment(name, labels, amount)` forms) without creating or touching any series; `0` is a valid amount at the non-negative boundary and leaves the value unchanged (recording the series at `0` if it was new).
- `Metrics.gauge(name, value)` and `Metrics.gauge(name, labels, value)` to set the exact value of a series, overwriting whatever was there before.
- `Metrics.get(name, labels)` to give me back the current value of that specific series, or `nil` if that exact series doesn't exist.
- `Metrics.get(name)` to give me the **aggregate** across all label combinations for that name — the sum of every series' value — or `nil` if the name has no series at all.
- `Metrics.series(name)` to return a list of `%{labels: labels_map, value: value}`, one entry per label combination recorded under `name` (order doesn't matter), or `[]` if the name has no series.
- `Metrics.reset(name, labels)` to set one specific series back to `0`, and `Metrics.reset(name)` to set *every* series under `name` back to `0`, leaving series recorded under other names untouched.
- `Metrics.all()` to return a map keyed by `{name, labels_map}` mapping to each series' value.

A couple of things that apply throughout: the `labels_map` you hand back (from `series/1` and `all/0`) has to be a plain map equal to what was passed in, regardless of the original key order. The ETS table needs to be public and named so `increment` can bypass the owning process — the GenServer exists only to own the table. Stick to OTP/stdlib, no external dependencies. Send me the complete implementation in a single file.
